//! This file contains a mapping of Windows time zone identifiers to IANA (AKA Olson) time zone identifiers.
//! It maps Windows (TimeZone key name, territory name) pairs to a list of IANA identifiers.
//!
//! The XML version uses territory "001" to indicate the default if none of the other territories match. This
//! file uses null to indicate such cases.
//!
//! Taken from the unicode CLDR project: https://cldr.unicode.org/development/development-process/design-proposals/extended-windows-olson-zid-mapping
//!
//! From CLDR release v44, 2023-10-31

pub const TimeZoneTerritory = std.meta.Tuple(&[_]type{ []const u16, ?[]const u16 });
pub const WindowsToIANAHashmap = std.HashMapUnmanaged(TimeZoneTerritory, []const chrono.tz.Identifier, TimeZoneTerritoryContext, 80);

pub fn constructWindowsToIANAHashmap(gpa: std.mem.Allocator) !WindowsToIANAHashmap {
    var map = WindowsToIANAHashmap{};
    try map.ensureUnusedCapacity(gpa, DATA.len);
    for (DATA) |datapoint| {
        var identifiers = std.ArrayList(chrono.tz.Identifier).init(gpa);
        defer identifiers.deinit();
        var iana_identifier_iter = std.mem.splitScalar(u8, datapoint.iana_identifiers, ' ');
        while (iana_identifier_iter.next()) |iana_identifier_string| {
            const iana_identifier = chrono.tz.Identifier.parse(iana_identifier_string) catch unreachable; // We are shipping all the data; it better parse
            try identifiers.append(iana_identifier);
        }

        var key: TimeZoneTerritory = undefined;

        {
            const timezone_key_utf16 = try gpa.alloc(u16, datapoint.windows_key.len);
            errdefer gpa.free(timezone_key_utf16);

            const timezone_key_utf16_len = try std.unicode.utf8ToUtf16Le(timezone_key_utf16, datapoint.windows_key);
            std.debug.assert(timezone_key_utf16_len == datapoint.windows_key.len);

            key[0] = timezone_key_utf16;
        }

        if (datapoint.windows_territory) |territory| {
            const territory_utf16 = try gpa.alloc(u16, territory.len);
            const territory_utf16_len = try std.unicode.utf8ToUtf16Le(territory_utf16, territory);
            std.debug.assert(territory_utf16_len == territory.len);

            key[1] = territory_utf16;
        } else {
            key[1] = null;
        }

        map.putAssumeCapacity(key, try identifiers.toOwnedSlice());
    }

    return map;
}

pub fn freeWindowsToIANAHashmap(gpa: std.mem.Allocator, map: WindowsToIANAHashmap) void {
    var iter = map.keyIterator();
    while (iter.next()) |key| {
        gpa.free(key[0]);
        gpa.free(key[1]);
    }
    map.deinit();
}

pub const TimeZoneTerritoryContext = struct {
    pub fn hash(this: @This(), tz_key: TimeZoneTerritory) u64 {
        _ = this;
        var wy_hash = std.hash.Wyhash.init(0);
        wy_hash.update(std.mem.sliceAsBytes(tz_key[0]));
        wy_hash.update(&[_]u8{ 0, 0 });
        if (tz_key[1]) |territory| wy_hash.update(std.mem.sliceAsBytes(territory));
        return wy_hash.final();
    }
    pub fn eql(this: @This(), a: TimeZoneTerritory, b: TimeZoneTerritory) bool {
        _ = this;
        if (a[1]) |a_territory| {
            if (b[1]) |b_territory| {
                return std.mem.eql(u16, a[0], b[0]) and std.mem.eql(u16, a_territory, b_territory);
            } else {
                return false;
            }
        }
        return std.mem.eql(u16, a[0], b[0]);
    }
};

pub const OLSON_DB_VERSION = "2021a";
pub const WINDOWS_TZ_VERSION: std.os.windows.DWORD = 0x7e11800;

pub const WindowsToIANA = struct {
    windows_key: []const u8,
    windows_territory: ?[]const u8,
    /// A string containing space separated IANA identifiers
    iana_identifiers: []const u8,
};

pub const DATA = [_]WindowsToIANA{
    // <!-- (UTC-12:00) International Date Line West -->
    .{ .windows_key = "Dateline Standard Time", .windows_territory = null, .iana_identifiers = "Etc/GMT+12" },

    .{ .windows_key = "Dateline Standard Time", .windows_territory = null, .iana_identifiers = "Etc/GMT+12" },
    .{ .windows_key = "Dateline Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT+12" },

    // <!-- (UTC-11:00) Coordinated Universal Time-11 -->
    .{ .windows_key = "UTC-11", .windows_territory = null, .iana_identifiers = "Etc/GMT+11" },
    .{ .windows_key = "UTC-11", .windows_territory = "AS", .iana_identifiers = "Pacific/Pago_Pago" },
    .{ .windows_key = "UTC-11", .windows_territory = "NU", .iana_identifiers = "Pacific/Niue" },
    .{ .windows_key = "UTC-11", .windows_territory = "UM", .iana_identifiers = "Pacific/Midway" },
    .{ .windows_key = "UTC-11", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT+11" },

    // <!-- (UTC-10:00) Aleutian Islands -->
    .{ .windows_key = "Aleutian Standard Time", .windows_territory = null, .iana_identifiers = "America/Adak" },
    .{ .windows_key = "Aleutian Standard Time", .windows_territory = "US", .iana_identifiers = "America/Adak" },

    // <!-- (UTC-10:00) Hawaii -->
    .{ .windows_key = "Hawaiian Standard Time", .windows_territory = null, .iana_identifiers = "Pacific/Honolulu" },
    .{ .windows_key = "Hawaiian Standard Time", .windows_territory = "CK", .iana_identifiers = "Pacific/Rarotonga" },
    .{ .windows_key = "Hawaiian Standard Time", .windows_territory = "PF", .iana_identifiers = "Pacific/Tahiti" },
    .{ .windows_key = "Hawaiian Standard Time", .windows_territory = "UM", .iana_identifiers = "Pacific/Johnston" },
    .{ .windows_key = "Hawaiian Standard Time", .windows_territory = "US", .iana_identifiers = "Pacific/Honolulu" },
    .{ .windows_key = "Hawaiian Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT+10" },

    // <!-- (UTC-09:30) Marquesas Islands -->
    .{ .windows_key = "Marquesas Standard Time", .windows_territory = null, .iana_identifiers = "Pacific/Marquesas" },
    .{ .windows_key = "Marquesas Standard Time", .windows_territory = "PF", .iana_identifiers = "Pacific/Marquesas" },

    // <!-- (UTC-09:00) Alaska -->
    .{ .windows_key = "Alaskan Standard Time", .windows_territory = null, .iana_identifiers = "America/Anchorage" },
    .{ .windows_key = "Alaskan Standard Time", .windows_territory = "US", .iana_identifiers = "America/Anchorage America/Juneau America/Metlakatla America/Nome America/Sitka America/Yakutat" },

    // <!-- (UTC-09:00) Coordinated Universal Time-09 -->
    .{ .windows_key = "UTC-09", .windows_territory = null, .iana_identifiers = "Etc/GMT+9" },
    .{ .windows_key = "UTC-09", .windows_territory = "PF", .iana_identifiers = "Pacific/Gambier" },
    .{ .windows_key = "UTC-09", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT+9" },

    // <!-- (UTC-08:00) Baja California -->
    .{ .windows_key = "Pacific Standard Time (Mexico)", .windows_territory = null, .iana_identifiers = "America/Tijuana" },
    .{ .windows_key = "Pacific Standard Time (Mexico)", .windows_territory = "MX", .iana_identifiers = "America/Tijuana America/Santa_Isabel" },

    // <!-- (UTC-08:00) Coordinated Universal Time-08 -->
    .{ .windows_key = "UTC-08", .windows_territory = null, .iana_identifiers = "Etc/GMT+8" },
    .{ .windows_key = "UTC-08", .windows_territory = "PN", .iana_identifiers = "Pacific/Pitcairn" },
    .{ .windows_key = "UTC-08", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT+8" },

    // <!-- (UTC-08:00) Pacific Time (US & Canada) -->
    .{ .windows_key = "Pacific Standard Time", .windows_territory = null, .iana_identifiers = "America/Los_Angeles" },
    .{ .windows_key = "Pacific Standard Time", .windows_territory = "CA", .iana_identifiers = "America/Vancouver" },
    .{ .windows_key = "Pacific Standard Time", .windows_territory = "US", .iana_identifiers = "America/Los_Angeles" },
    .{ .windows_key = "Pacific Standard Time", .windows_territory = "ZZ", .iana_identifiers = "PST8PDT" },

    // <!-- (UTC-07:00) Arizona -->
    .{ .windows_key = "US Mountain Standard Time", .windows_territory = null, .iana_identifiers = "America/Phoenix" },
    .{ .windows_key = "US Mountain Standard Time", .windows_territory = "CA", .iana_identifiers = "America/Creston America/Dawson_Creek America/Fort_Nelson" },
    .{ .windows_key = "US Mountain Standard Time", .windows_territory = "MX", .iana_identifiers = "America/Hermosillo" },
    .{ .windows_key = "US Mountain Standard Time", .windows_territory = "US", .iana_identifiers = "America/Phoenix" },
    .{ .windows_key = "US Mountain Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT+7" },

    // <!-- (UTC-07:00) Chihuahua, La Paz, Mazatlan -->
    .{ .windows_key = "Mountain Standard Time (Mexico)", .windows_territory = null, .iana_identifiers = "America/Mazatlan" },
    .{ .windows_key = "Mountain Standard Time (Mexico)", .windows_territory = "MX", .iana_identifiers = "America/Mazatlan" },

    // <!-- (UTC-07:00) Mountain Time (US & Canada) -->
    .{ .windows_key = "Mountain Standard Time", .windows_territory = null, .iana_identifiers = "America/Denver" },
    .{ .windows_key = "Mountain Standard Time", .windows_territory = "CA", .iana_identifiers = "America/Edmonton America/Cambridge_Bay America/Inuvik America/Yellowknife" },
    .{ .windows_key = "Mountain Standard Time", .windows_territory = "MX", .iana_identifiers = "America/Ciudad_Juarez" },
    .{ .windows_key = "Mountain Standard Time", .windows_territory = "US", .iana_identifiers = "America/Denver America/Boise" },
    .{ .windows_key = "Mountain Standard Time", .windows_territory = "ZZ", .iana_identifiers = "MST7MDT" },

    // <!-- (UTC-07:00) Yukon -->
    .{ .windows_key = "Yukon Standard Time", .windows_territory = null, .iana_identifiers = "America/Whitehorse" },
    .{ .windows_key = "Yukon Standard Time", .windows_territory = "CA", .iana_identifiers = "America/Whitehorse America/Dawson" },

    // <!-- (UTC-06:00) Central America -->
    .{ .windows_key = "Central America Standard Time", .windows_territory = null, .iana_identifiers = "America/Guatemala" },
    .{ .windows_key = "Central America Standard Time", .windows_territory = "BZ", .iana_identifiers = "America/Belize" },
    .{ .windows_key = "Central America Standard Time", .windows_territory = "CR", .iana_identifiers = "America/Costa_Rica" },
    .{ .windows_key = "Central America Standard Time", .windows_territory = "EC", .iana_identifiers = "Pacific/Galapagos" },
    .{ .windows_key = "Central America Standard Time", .windows_territory = "GT", .iana_identifiers = "America/Guatemala" },
    .{ .windows_key = "Central America Standard Time", .windows_territory = "HN", .iana_identifiers = "America/Tegucigalpa" },
    .{ .windows_key = "Central America Standard Time", .windows_territory = "NI", .iana_identifiers = "America/Managua" },
    .{ .windows_key = "Central America Standard Time", .windows_territory = "SV", .iana_identifiers = "America/El_Salvador" },
    .{ .windows_key = "Central America Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT+6" },

    // <!-- (UTC-06:00) Central Time (US & Canada) -->
    .{ .windows_key = "Central Standard Time", .windows_territory = null, .iana_identifiers = "America/Chicago" },
    .{ .windows_key = "Central Standard Time", .windows_territory = "CA", .iana_identifiers = "America/Winnipeg America/Rainy_River America/Rankin_Inlet America/Resolute" },
    .{ .windows_key = "Central Standard Time", .windows_territory = "MX", .iana_identifiers = "America/Matamoros America/Ojinaga" },
    .{ .windows_key = "Central Standard Time", .windows_territory = "US", .iana_identifiers = "America/Chicago America/Indiana/Knox America/Indiana/Tell_City America/Menominee America/North_Dakota/Beulah America/North_Dakota/Center America/North_Dakota/New_Salem" },
    .{ .windows_key = "Central Standard Time", .windows_territory = "ZZ", .iana_identifiers = "CST6CDT" },

    // <!-- (UTC-06:00) Easter Island -->
    .{ .windows_key = "Easter Island Standard Time", .windows_territory = null, .iana_identifiers = "Pacific/Easter" },
    .{ .windows_key = "Easter Island Standard Time", .windows_territory = "CL", .iana_identifiers = "Pacific/Easter" },

    // <!-- (UTC-06:00) Guadalajara, Mexico City, Monterrey -->
    .{ .windows_key = "Central Standard Time (Mexico)", .windows_territory = null, .iana_identifiers = "America/Mexico_City" },
    .{ .windows_key = "Central Standard Time (Mexico)", .windows_territory = "MX", .iana_identifiers = "America/Mexico_City America/Bahia_Banderas America/Merida America/Monterrey America/Chihuahua " },

    // <!-- (UTC-06:00) Saskatchewan -->
    .{ .windows_key = "Canada Central Standard Time", .windows_territory = null, .iana_identifiers = "America/Regina" },
    .{ .windows_key = "Canada Central Standard Time", .windows_territory = "CA", .iana_identifiers = "America/Regina America/Swift_Current" },

    // <!-- (UTC-05:00) Bogota, Lima, Quito, Rio Branco -->
    .{ .windows_key = "SA Pacific Standard Time", .windows_territory = null, .iana_identifiers = "America/Bogota" },
    .{ .windows_key = "SA Pacific Standard Time", .windows_territory = "BR", .iana_identifiers = "America/Rio_Branco America/Eirunepe" },
    .{ .windows_key = "SA Pacific Standard Time", .windows_territory = "CA", .iana_identifiers = "America/Coral_Harbour" },
    .{ .windows_key = "SA Pacific Standard Time", .windows_territory = "CO", .iana_identifiers = "America/Bogota" },
    .{ .windows_key = "SA Pacific Standard Time", .windows_territory = "EC", .iana_identifiers = "America/Guayaquil" },
    .{ .windows_key = "SA Pacific Standard Time", .windows_territory = "JM", .iana_identifiers = "America/Jamaica" },
    .{ .windows_key = "SA Pacific Standard Time", .windows_territory = "KY", .iana_identifiers = "America/Cayman" },
    .{ .windows_key = "SA Pacific Standard Time", .windows_territory = "PA", .iana_identifiers = "America/Panama" },
    .{ .windows_key = "SA Pacific Standard Time", .windows_territory = "PE", .iana_identifiers = "America/Lima" },
    .{ .windows_key = "SA Pacific Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT+5" },

    // <!-- (UTC-05:00) Chetumal -->
    .{ .windows_key = "Eastern Standard Time (Mexico)", .windows_territory = null, .iana_identifiers = "America/Cancun" },
    .{ .windows_key = "Eastern Standard Time (Mexico)", .windows_territory = "MX", .iana_identifiers = "America/Cancun" },

    // <!-- (UTC-05:00) Eastern Time (US & Canada) -->
    .{ .windows_key = "Eastern Standard Time", .windows_territory = null, .iana_identifiers = "America/New_York" },
    .{ .windows_key = "Eastern Standard Time", .windows_territory = "BS", .iana_identifiers = "America/Nassau" },
    .{ .windows_key = "Eastern Standard Time", .windows_territory = "CA", .iana_identifiers = "America/Toronto America/Iqaluit America/Montreal America/Nipigon America/Pangnirtung America/Thunder_Bay" },
    .{ .windows_key = "Eastern Standard Time", .windows_territory = "US", .iana_identifiers = "America/New_York America/Detroit America/Indiana/Petersburg America/Indiana/Vincennes America/Indiana/Winamac America/Kentucky/Monticello America/Louisville" },
    .{ .windows_key = "Eastern Standard Time", .windows_territory = "ZZ", .iana_identifiers = "EST5EDT" },

    // <!-- (UTC-05:00) Haiti -->
    .{ .windows_key = "Haiti Standard Time", .windows_territory = null, .iana_identifiers = "America/Port-au-Prince" },
    .{ .windows_key = "Haiti Standard Time", .windows_territory = "HT", .iana_identifiers = "America/Port-au-Prince" },

    // <!-- (UTC-05:00) Havana -->
    .{ .windows_key = "Cuba Standard Time", .windows_territory = null, .iana_identifiers = "America/Havana" },
    .{ .windows_key = "Cuba Standard Time", .windows_territory = "CU", .iana_identifiers = "America/Havana" },

    // <!-- (UTC-05:00) Indiana (East) -->
    .{ .windows_key = "US Eastern Standard Time", .windows_territory = null, .iana_identifiers = "America/Indianapolis" },
    .{ .windows_key = "US Eastern Standard Time", .windows_territory = "US", .iana_identifiers = "America/Indianapolis America/Indiana/Marengo America/Indiana/Vevay" },

    // <!-- (UTC-05:00) Turks and Caicos -->
    .{ .windows_key = "Turks And Caicos Standard Time", .windows_territory = null, .iana_identifiers = "America/Grand_Turk" },
    .{ .windows_key = "Turks And Caicos Standard Time", .windows_territory = "TC", .iana_identifiers = "America/Grand_Turk" },

    // <!-- (UTC-04:00) Asuncion -->
    .{ .windows_key = "Paraguay Standard Time", .windows_territory = null, .iana_identifiers = "America/Asuncion" },
    .{ .windows_key = "Paraguay Standard Time", .windows_territory = "PY", .iana_identifiers = "America/Asuncion" },

    // <!-- (UTC-04:00) Atlantic Time (Canada) -->
    .{ .windows_key = "Atlantic Standard Time", .windows_territory = null, .iana_identifiers = "America/Halifax" },
    .{ .windows_key = "Atlantic Standard Time", .windows_territory = "BM", .iana_identifiers = "Atlantic/Bermuda" },
    .{ .windows_key = "Atlantic Standard Time", .windows_territory = "CA", .iana_identifiers = "America/Halifax America/Glace_Bay America/Goose_Bay America/Moncton" },
    .{ .windows_key = "Atlantic Standard Time", .windows_territory = "GL", .iana_identifiers = "America/Thule" },

    // <!-- (UTC-04:00) Caracas -->
    .{ .windows_key = "Venezuela Standard Time", .windows_territory = null, .iana_identifiers = "America/Caracas" },
    .{ .windows_key = "Venezuela Standard Time", .windows_territory = "VE", .iana_identifiers = "America/Caracas" },

    // <!-- (UTC-04:00) Cuiaba -->
    .{ .windows_key = "Central Brazilian Standard Time", .windows_territory = null, .iana_identifiers = "America/Cuiaba" },
    .{ .windows_key = "Central Brazilian Standard Time", .windows_territory = "BR", .iana_identifiers = "America/Cuiaba America/Campo_Grande" },

    // <!-- (UTC-04:00) Georgetown, La Paz, Manaus, San Juan -->
    .{ .windows_key = "SA Western Standard Time", .windows_territory = null, .iana_identifiers = "America/La_Paz" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "AG", .iana_identifiers = "America/Antigua" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "AI", .iana_identifiers = "America/Anguilla" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "AW", .iana_identifiers = "America/Aruba" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "BB", .iana_identifiers = "America/Barbados" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "BL", .iana_identifiers = "America/St_Barthelemy" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "BO", .iana_identifiers = "America/La_Paz" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "BQ", .iana_identifiers = "America/Kralendijk" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "BR", .iana_identifiers = "America/Manaus America/Boa_Vista America/Porto_Velho" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "CA", .iana_identifiers = "America/Blanc-Sablon" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "CW", .iana_identifiers = "America/Curacao" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "DM", .iana_identifiers = "America/Dominica" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "DO", .iana_identifiers = "America/Santo_Domingo" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "GD", .iana_identifiers = "America/Grenada" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "GP", .iana_identifiers = "America/Guadeloupe" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "GY", .iana_identifiers = "America/Guyana" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "KN", .iana_identifiers = "America/St_Kitts" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "LC", .iana_identifiers = "America/St_Lucia" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "MF", .iana_identifiers = "America/Marigot" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "MQ", .iana_identifiers = "America/Martinique" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "MS", .iana_identifiers = "America/Montserrat" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "PR", .iana_identifiers = "America/Puerto_Rico" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "SX", .iana_identifiers = "America/Lower_Princes" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "TT", .iana_identifiers = "America/Port_of_Spain" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "VC", .iana_identifiers = "America/St_Vincent" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "VG", .iana_identifiers = "America/Tortola" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "VI", .iana_identifiers = "America/St_Thomas" },
    .{ .windows_key = "SA Western Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT+4" },

    // <!-- (UTC-04:00) Santiago -->
    .{ .windows_key = "Pacific SA Standard Time", .windows_territory = null, .iana_identifiers = "America/Santiago" },
    .{ .windows_key = "Pacific SA Standard Time", .windows_territory = "CL", .iana_identifiers = "America/Santiago" },

    // <!-- (UTC-03:30) Newfoundland -->
    .{ .windows_key = "Newfoundland Standard Time", .windows_territory = null, .iana_identifiers = "America/St_Johns" },
    .{ .windows_key = "Newfoundland Standard Time", .windows_territory = "CA", .iana_identifiers = "America/St_Johns" },

    // <!-- (UTC-03:00) Araguaina -->
    .{ .windows_key = "Tocantins Standard Time", .windows_territory = null, .iana_identifiers = "America/Araguaina" },
    .{ .windows_key = "Tocantins Standard Time", .windows_territory = "BR", .iana_identifiers = "America/Araguaina" },

    // <!-- (UTC-03:00) Brasilia -->
    .{ .windows_key = "E. South America Standard Time", .windows_territory = null, .iana_identifiers = "America/Sao_Paulo" },
    .{ .windows_key = "E. South America Standard Time", .windows_territory = "BR", .iana_identifiers = "America/Sao_Paulo" },

    // <!-- (UTC-03:00) Cayenne, Fortaleza -->
    .{ .windows_key = "SA Eastern Standard Time", .windows_territory = null, .iana_identifiers = "America/Cayenne" },
    .{ .windows_key = "SA Eastern Standard Time", .windows_territory = "AQ", .iana_identifiers = "Antarctica/Rothera Antarctica/Palmer" },
    .{ .windows_key = "SA Eastern Standard Time", .windows_territory = "BR", .iana_identifiers = "America/Fortaleza America/Belem America/Maceio America/Recife America/Santarem" },
    .{ .windows_key = "SA Eastern Standard Time", .windows_territory = "FK", .iana_identifiers = "Atlantic/Stanley" },
    .{ .windows_key = "SA Eastern Standard Time", .windows_territory = "GF", .iana_identifiers = "America/Cayenne" },
    .{ .windows_key = "SA Eastern Standard Time", .windows_territory = "SR", .iana_identifiers = "America/Paramaribo" },
    .{ .windows_key = "SA Eastern Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT+3" },

    // <!-- (UTC-03:00) City of Buenos Aires -->
    .{ .windows_key = "Argentina Standard Time", .windows_territory = null, .iana_identifiers = "America/Buenos_Aires" },
    .{ .windows_key = "Argentina Standard Time", .windows_territory = "AR", .iana_identifiers = "America/Buenos_Aires America/Argentina/La_Rioja America/Argentina/Rio_Gallegos America/Argentina/Salta America/Argentina/San_Juan America/Argentina/San_Luis America/Argentina/Tucuman America/Argentina/Ushuaia America/Catamarca America/Cordoba America/Jujuy America/Mendoza" },

    // <!-- (UTC-03:00) Greenland -->
    .{ .windows_key = "Greenland Standard Time", .windows_territory = null, .iana_identifiers = "America/Godthab" },
    .{ .windows_key = "Greenland Standard Time", .windows_territory = "GL", .iana_identifiers = "America/Godthab" },

    // <!-- (UTC-03:00) Montevideo -->
    .{ .windows_key = "Montevideo Standard Time", .windows_territory = null, .iana_identifiers = "America/Montevideo" },
    .{ .windows_key = "Montevideo Standard Time", .windows_territory = "UY", .iana_identifiers = "America/Montevideo" },

    // <!-- (UTC-03:00) Punta Arenas -->
    .{ .windows_key = "Magallanes Standard Time", .windows_territory = null, .iana_identifiers = "America/Punta_Arenas" },
    .{ .windows_key = "Magallanes Standard Time", .windows_territory = "CL", .iana_identifiers = "America/Punta_Arenas" },

    // <!-- (UTC-03:00) Saint Pierre and Miquelon -->
    .{ .windows_key = "Saint Pierre Standard Time", .windows_territory = null, .iana_identifiers = "America/Miquelon" },
    .{ .windows_key = "Saint Pierre Standard Time", .windows_territory = "PM", .iana_identifiers = "America/Miquelon" },

    // <!-- (UTC-03:00) Salvador -->
    .{ .windows_key = "Bahia Standard Time", .windows_territory = null, .iana_identifiers = "America/Bahia" },
    .{ .windows_key = "Bahia Standard Time", .windows_territory = "BR", .iana_identifiers = "America/Bahia" },

    // <!-- (UTC-02:00) Coordinated Universal Time-02 -->
    .{ .windows_key = "UTC-02", .windows_territory = null, .iana_identifiers = "Etc/GMT+2" },
    .{ .windows_key = "UTC-02", .windows_territory = "BR", .iana_identifiers = "America/Noronha" },
    .{ .windows_key = "UTC-02", .windows_territory = "GS", .iana_identifiers = "Atlantic/South_Georgia" },
    .{ .windows_key = "UTC-02", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT+2" },

    // <!-- (UTC-01:00) Azores -->
    .{ .windows_key = "Azores Standard Time", .windows_territory = null, .iana_identifiers = "Atlantic/Azores" },
    .{ .windows_key = "Azores Standard Time", .windows_territory = "GL", .iana_identifiers = "America/Scoresbysund" },
    .{ .windows_key = "Azores Standard Time", .windows_territory = "PT", .iana_identifiers = "Atlantic/Azores" },

    // <!-- (UTC-01:00) Cabo Verde Is. -->
    .{ .windows_key = "Cape Verde Standard Time", .windows_territory = null, .iana_identifiers = "Atlantic/Cape_Verde" },
    .{ .windows_key = "Cape Verde Standard Time", .windows_territory = "CV", .iana_identifiers = "Atlantic/Cape_Verde" },
    .{ .windows_key = "Cape Verde Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT+1" },

    // <!-- (UTC) Coordinated Universal Time -->
    .{ .windows_key = "UTC", .windows_territory = null, .iana_identifiers = "Etc/UTC" },
    .{ .windows_key = "UTC", .windows_territory = "ZZ", .iana_identifiers = "Etc/UTC Etc/GMT" },

    // <!-- (UTC+00:00) Dublin, Edinburgh, Lisbon, London -->
    .{ .windows_key = "GMT Standard Time", .windows_territory = null, .iana_identifiers = "Europe/London" },
    .{ .windows_key = "GMT Standard Time", .windows_territory = "ES", .iana_identifiers = "Atlantic/Canary" },
    .{ .windows_key = "GMT Standard Time", .windows_territory = "FO", .iana_identifiers = "Atlantic/Faeroe" },
    .{ .windows_key = "GMT Standard Time", .windows_territory = "GB", .iana_identifiers = "Europe/London" },
    .{ .windows_key = "GMT Standard Time", .windows_territory = "GG", .iana_identifiers = "Europe/Guernsey" },
    .{ .windows_key = "GMT Standard Time", .windows_territory = "IE", .iana_identifiers = "Europe/Dublin" },
    .{ .windows_key = "GMT Standard Time", .windows_territory = "IM", .iana_identifiers = "Europe/Isle_of_Man" },
    .{ .windows_key = "GMT Standard Time", .windows_territory = "JE", .iana_identifiers = "Europe/Jersey" },
    .{ .windows_key = "GMT Standard Time", .windows_territory = "PT", .iana_identifiers = "Europe/Lisbon Atlantic/Madeira" },

    // <!-- (UTC+00:00) Monrovia, Reykjavik -->
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = null, .iana_identifiers = "Atlantic/Reykjavik" },
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = "BF", .iana_identifiers = "Africa/Ouagadougou" },
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = "CI", .iana_identifiers = "Africa/Abidjan" },
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = "GH", .iana_identifiers = "Africa/Accra" },
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = "GL", .iana_identifiers = "America/Danmarkshavn" },
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = "GM", .iana_identifiers = "Africa/Banjul" },
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = "GN", .iana_identifiers = "Africa/Conakry" },
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = "GW", .iana_identifiers = "Africa/Bissau" },
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = "IS", .iana_identifiers = "Atlantic/Reykjavik" },
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = "LR", .iana_identifiers = "Africa/Monrovia" },
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = "ML", .iana_identifiers = "Africa/Bamako" },
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = "MR", .iana_identifiers = "Africa/Nouakchott" },
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = "SH", .iana_identifiers = "Atlantic/St_Helena" },
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = "SL", .iana_identifiers = "Africa/Freetown" },
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = "SN", .iana_identifiers = "Africa/Dakar" },
    .{ .windows_key = "Greenwich Standard Time", .windows_territory = "TG", .iana_identifiers = "Africa/Lome" },

    // <!-- (UTC+00:00) Sao Tome -->
    .{ .windows_key = "Sao Tome Standard Time", .windows_territory = null, .iana_identifiers = "Africa/Sao_Tome" },
    .{ .windows_key = "Sao Tome Standard Time", .windows_territory = "ST", .iana_identifiers = "Africa/Sao_Tome" },

    // <!-- (UTC+01:00) Casablanca -->
    .{ .windows_key = "Morocco Standard Time", .windows_territory = null, .iana_identifiers = "Africa/Casablanca" },
    .{ .windows_key = "Morocco Standard Time", .windows_territory = "EH", .iana_identifiers = "Africa/El_Aaiun" },
    .{ .windows_key = "Morocco Standard Time", .windows_territory = "MA", .iana_identifiers = "Africa/Casablanca" },

    // <!-- (UTC+01:00) Amsterdam, Berlin, Bern, Rome, Stockholm, Vienna -->
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = null, .iana_identifiers = "Europe/Berlin" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "AD", .iana_identifiers = "Europe/Andorra" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "AT", .iana_identifiers = "Europe/Vienna" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "CH", .iana_identifiers = "Europe/Zurich" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "DE", .iana_identifiers = "Europe/Berlin Europe/Busingen" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "GI", .iana_identifiers = "Europe/Gibraltar" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "IT", .iana_identifiers = "Europe/Rome" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "LI", .iana_identifiers = "Europe/Vaduz" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "LU", .iana_identifiers = "Europe/Luxembourg" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "MC", .iana_identifiers = "Europe/Monaco" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "MT", .iana_identifiers = "Europe/Malta" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "NL", .iana_identifiers = "Europe/Amsterdam" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "NO", .iana_identifiers = "Europe/Oslo" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "SE", .iana_identifiers = "Europe/Stockholm" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "SJ", .iana_identifiers = "Arctic/Longyearbyen" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "SM", .iana_identifiers = "Europe/San_Marino" },
    .{ .windows_key = "W. Europe Standard Time", .windows_territory = "VA", .iana_identifiers = "Europe/Vatican" },

    // <!-- (UTC+01:00) Belgrade, Bratislava, Budapest, Ljubljana, Prague -->
    .{ .windows_key = "Central Europe Standard Time", .windows_territory = null, .iana_identifiers = "Europe/Budapest" },
    .{ .windows_key = "Central Europe Standard Time", .windows_territory = "AL", .iana_identifiers = "Europe/Tirane" },
    .{ .windows_key = "Central Europe Standard Time", .windows_territory = "CZ", .iana_identifiers = "Europe/Prague" },
    .{ .windows_key = "Central Europe Standard Time", .windows_territory = "HU", .iana_identifiers = "Europe/Budapest" },
    .{ .windows_key = "Central Europe Standard Time", .windows_territory = "ME", .iana_identifiers = "Europe/Podgorica" },
    .{ .windows_key = "Central Europe Standard Time", .windows_territory = "RS", .iana_identifiers = "Europe/Belgrade" },
    .{ .windows_key = "Central Europe Standard Time", .windows_territory = "SI", .iana_identifiers = "Europe/Ljubljana" },
    .{ .windows_key = "Central Europe Standard Time", .windows_territory = "SK", .iana_identifiers = "Europe/Bratislava" },

    // <!-- (UTC+01:00) Brussels, Copenhagen, Madrid, Paris -->
    .{ .windows_key = "Romance Standard Time", .windows_territory = null, .iana_identifiers = "Europe/Paris" },
    .{ .windows_key = "Romance Standard Time", .windows_territory = "BE", .iana_identifiers = "Europe/Brussels" },
    .{ .windows_key = "Romance Standard Time", .windows_territory = "DK", .iana_identifiers = "Europe/Copenhagen" },
    .{ .windows_key = "Romance Standard Time", .windows_territory = "ES", .iana_identifiers = "Europe/Madrid Africa/Ceuta" },
    .{ .windows_key = "Romance Standard Time", .windows_territory = "FR", .iana_identifiers = "Europe/Paris" },

    // <!-- (UTC+01:00) Sarajevo, Skopje, Warsaw, Zagreb -->
    .{ .windows_key = "Central European Standard Time", .windows_territory = null, .iana_identifiers = "Europe/Warsaw" },
    .{ .windows_key = "Central European Standard Time", .windows_territory = "BA", .iana_identifiers = "Europe/Sarajevo" },
    .{ .windows_key = "Central European Standard Time", .windows_territory = "HR", .iana_identifiers = "Europe/Zagreb" },
    .{ .windows_key = "Central European Standard Time", .windows_territory = "MK", .iana_identifiers = "Europe/Skopje" },
    .{ .windows_key = "Central European Standard Time", .windows_territory = "PL", .iana_identifiers = "Europe/Warsaw" },

    // <!-- (UTC+01:00) West Central Africa -->
    .{ .windows_key = "W. Central Africa Standard Time", .windows_territory = null, .iana_identifiers = "Africa/Lagos" },
    .{ .windows_key = "W. Central Africa Standard Time", .windows_territory = "AO", .iana_identifiers = "Africa/Luanda" },
    .{ .windows_key = "W. Central Africa Standard Time", .windows_territory = "BJ", .iana_identifiers = "Africa/Porto-Novo" },
    .{ .windows_key = "W. Central Africa Standard Time", .windows_territory = "CD", .iana_identifiers = "Africa/Kinshasa" },
    .{ .windows_key = "W. Central Africa Standard Time", .windows_territory = "CF", .iana_identifiers = "Africa/Bangui" },
    .{ .windows_key = "W. Central Africa Standard Time", .windows_territory = "CG", .iana_identifiers = "Africa/Brazzaville" },
    .{ .windows_key = "W. Central Africa Standard Time", .windows_territory = "CM", .iana_identifiers = "Africa/Douala" },
    .{ .windows_key = "W. Central Africa Standard Time", .windows_territory = "DZ", .iana_identifiers = "Africa/Algiers" },
    .{ .windows_key = "W. Central Africa Standard Time", .windows_territory = "GA", .iana_identifiers = "Africa/Libreville" },
    .{ .windows_key = "W. Central Africa Standard Time", .windows_territory = "GQ", .iana_identifiers = "Africa/Malabo" },
    .{ .windows_key = "W. Central Africa Standard Time", .windows_territory = "NE", .iana_identifiers = "Africa/Niamey" },
    .{ .windows_key = "W. Central Africa Standard Time", .windows_territory = "NG", .iana_identifiers = "Africa/Lagos" },
    .{ .windows_key = "W. Central Africa Standard Time", .windows_territory = "TD", .iana_identifiers = "Africa/Ndjamena" },
    .{ .windows_key = "W. Central Africa Standard Time", .windows_territory = "TN", .iana_identifiers = "Africa/Tunis" },
    .{ .windows_key = "W. Central Africa Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT-1" },

    // <!-- (UTC+02:00) Amman -->
    .{ .windows_key = "Jordan Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Amman" },
    .{ .windows_key = "Jordan Standard Time", .windows_territory = "JO", .iana_identifiers = "Asia/Amman" },

    // <!-- (UTC+02:00) Athens, Bucharest -->
    .{ .windows_key = "GTB Standard Time", .windows_territory = null, .iana_identifiers = "Europe/Bucharest" },
    .{ .windows_key = "GTB Standard Time", .windows_territory = "CY", .iana_identifiers = "Asia/Nicosia Asia/Famagusta" },
    .{ .windows_key = "GTB Standard Time", .windows_territory = "GR", .iana_identifiers = "Europe/Athens" },
    .{ .windows_key = "GTB Standard Time", .windows_territory = "RO", .iana_identifiers = "Europe/Bucharest" },

    // <!-- (UTC+02:00) Beirut -->
    .{ .windows_key = "Middle East Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Beirut" },
    .{ .windows_key = "Middle East Standard Time", .windows_territory = "LB", .iana_identifiers = "Asia/Beirut" },

    // <!-- (UTC+02:00) Cairo -->
    .{ .windows_key = "Egypt Standard Time", .windows_territory = null, .iana_identifiers = "Africa/Cairo" },
    .{ .windows_key = "Egypt Standard Time", .windows_territory = "EG", .iana_identifiers = "Africa/Cairo" },

    // <!-- (UTC+02:00) Chisinau -->
    .{ .windows_key = "E. Europe Standard Time", .windows_territory = null, .iana_identifiers = "Europe/Chisinau" },
    .{ .windows_key = "E. Europe Standard Time", .windows_territory = "MD", .iana_identifiers = "Europe/Chisinau" },

    // <!-- (UTC+02:00) Damascus -->
    .{ .windows_key = "Syria Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Damascus" },
    .{ .windows_key = "Syria Standard Time", .windows_territory = "SY", .iana_identifiers = "Asia/Damascus" },

    // <!-- (UTC+02:00) Gaza, Hebron -->
    .{ .windows_key = "West Bank Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Hebron" },
    .{ .windows_key = "West Bank Standard Time", .windows_territory = "PS", .iana_identifiers = "Asia/Hebron Asia/Gaza" },

    // <!-- (UTC+02:00) Harare, Pretoria -->
    .{ .windows_key = "South Africa Standard Time", .windows_territory = null, .iana_identifiers = "Africa/Johannesburg" },
    .{ .windows_key = "South Africa Standard Time", .windows_territory = "BI", .iana_identifiers = "Africa/Bujumbura" },
    .{ .windows_key = "South Africa Standard Time", .windows_territory = "BW", .iana_identifiers = "Africa/Gaborone" },
    .{ .windows_key = "South Africa Standard Time", .windows_territory = "CD", .iana_identifiers = "Africa/Lubumbashi" },
    .{ .windows_key = "South Africa Standard Time", .windows_territory = "LS", .iana_identifiers = "Africa/Maseru" },
    .{ .windows_key = "South Africa Standard Time", .windows_territory = "MW", .iana_identifiers = "Africa/Blantyre" },
    .{ .windows_key = "South Africa Standard Time", .windows_territory = "MZ", .iana_identifiers = "Africa/Maputo" },
    .{ .windows_key = "South Africa Standard Time", .windows_territory = "RW", .iana_identifiers = "Africa/Kigali" },
    .{ .windows_key = "South Africa Standard Time", .windows_territory = "SZ", .iana_identifiers = "Africa/Mbabane" },
    .{ .windows_key = "South Africa Standard Time", .windows_territory = "ZA", .iana_identifiers = "Africa/Johannesburg" },
    .{ .windows_key = "South Africa Standard Time", .windows_territory = "ZM", .iana_identifiers = "Africa/Lusaka" },
    .{ .windows_key = "South Africa Standard Time", .windows_territory = "ZW", .iana_identifiers = "Africa/Harare" },
    .{ .windows_key = "South Africa Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT-2" },

    // <!-- (UTC+02:00) Helsinki, Kyiv, Riga, Sofia, Tallinn, Vilnius -->
    .{ .windows_key = "FLE Standard Time", .windows_territory = null, .iana_identifiers = "Europe/Kiev" },
    .{ .windows_key = "FLE Standard Time", .windows_territory = "AX", .iana_identifiers = "Europe/Mariehamn" },
    .{ .windows_key = "FLE Standard Time", .windows_territory = "BG", .iana_identifiers = "Europe/Sofia" },
    .{ .windows_key = "FLE Standard Time", .windows_territory = "EE", .iana_identifiers = "Europe/Tallinn" },
    .{ .windows_key = "FLE Standard Time", .windows_territory = "FI", .iana_identifiers = "Europe/Helsinki" },
    .{ .windows_key = "FLE Standard Time", .windows_territory = "LT", .iana_identifiers = "Europe/Vilnius" },
    .{ .windows_key = "FLE Standard Time", .windows_territory = "LV", .iana_identifiers = "Europe/Riga" },
    .{ .windows_key = "FLE Standard Time", .windows_territory = "UA", .iana_identifiers = "Europe/Kiev Europe/Uzhgorod Europe/Zaporozhye" },

    // <!-- (UTC+02:00) Jerusalem -->
    .{ .windows_key = "Israel Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Jerusalem" },
    .{ .windows_key = "Israel Standard Time", .windows_territory = "IL", .iana_identifiers = "Asia/Jerusalem" },

    // <!-- (UTC+02:00) Juba -->
    .{ .windows_key = "South Sudan Standard Time", .windows_territory = null, .iana_identifiers = "Africa/Juba" },
    .{ .windows_key = "South Sudan Standard Time", .windows_territory = "SS", .iana_identifiers = "Africa/Juba" },

    // <!-- (UTC+02:00) Kaliningrad -->
    .{ .windows_key = "Kaliningrad Standard Time", .windows_territory = null, .iana_identifiers = "Europe/Kaliningrad" },
    .{ .windows_key = "Kaliningrad Standard Time", .windows_territory = "RU", .iana_identifiers = "Europe/Kaliningrad" },

    // <!-- (UTC+02:00) Khartoum -->
    .{ .windows_key = "Sudan Standard Time", .windows_territory = null, .iana_identifiers = "Africa/Khartoum" },
    .{ .windows_key = "Sudan Standard Time", .windows_territory = "SD", .iana_identifiers = "Africa/Khartoum" },

    // <!-- (UTC+02:00) Tripoli -->
    .{ .windows_key = "Libya Standard Time", .windows_territory = null, .iana_identifiers = "Africa/Tripoli" },
    .{ .windows_key = "Libya Standard Time", .windows_territory = "LY", .iana_identifiers = "Africa/Tripoli" },

    // <!-- (UTC+02:00) Windhoek -->
    .{ .windows_key = "Namibia Standard Time", .windows_territory = null, .iana_identifiers = "Africa/Windhoek" },
    .{ .windows_key = "Namibia Standard Time", .windows_territory = "NA", .iana_identifiers = "Africa/Windhoek" },

    // <!-- (UTC+03:00) Baghdad -->
    .{ .windows_key = "Arabic Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Baghdad" },
    .{ .windows_key = "Arabic Standard Time", .windows_territory = "IQ", .iana_identifiers = "Asia/Baghdad" },

    // <!-- (UTC+03:00) Istanbul -->
    .{ .windows_key = "Turkey Standard Time", .windows_territory = null, .iana_identifiers = "Europe/Istanbul" },
    .{ .windows_key = "Turkey Standard Time", .windows_territory = "TR", .iana_identifiers = "Europe/Istanbul" },

    // <!-- (UTC+03:00) Kuwait, Riyadh -->
    .{ .windows_key = "Arab Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Riyadh" },
    .{ .windows_key = "Arab Standard Time", .windows_territory = "BH", .iana_identifiers = "Asia/Bahrain" },
    .{ .windows_key = "Arab Standard Time", .windows_territory = "KW", .iana_identifiers = "Asia/Kuwait" },
    .{ .windows_key = "Arab Standard Time", .windows_territory = "QA", .iana_identifiers = "Asia/Qatar" },
    .{ .windows_key = "Arab Standard Time", .windows_territory = "SA", .iana_identifiers = "Asia/Riyadh" },
    .{ .windows_key = "Arab Standard Time", .windows_territory = "YE", .iana_identifiers = "Asia/Aden" },

    // <!-- (UTC+03:00) Minsk -->
    .{ .windows_key = "Belarus Standard Time", .windows_territory = null, .iana_identifiers = "Europe/Minsk" },
    .{ .windows_key = "Belarus Standard Time", .windows_territory = "BY", .iana_identifiers = "Europe/Minsk" },

    // <!-- (UTC+03:00) Moscow, St. Petersburg -->
    .{ .windows_key = "Russian Standard Time", .windows_territory = null, .iana_identifiers = "Europe/Moscow" },
    .{ .windows_key = "Russian Standard Time", .windows_territory = "RU", .iana_identifiers = "Europe/Moscow Europe/Kirov" },
    .{ .windows_key = "Russian Standard Time", .windows_territory = "UA", .iana_identifiers = "Europe/Simferopol" },

    // <!-- (UTC+03:00) Nairobi -->
    .{ .windows_key = "E. Africa Standard Time", .windows_territory = null, .iana_identifiers = "Africa/Nairobi" },
    .{ .windows_key = "E. Africa Standard Time", .windows_territory = "AQ", .iana_identifiers = "Antarctica/Syowa" },
    .{ .windows_key = "E. Africa Standard Time", .windows_territory = "DJ", .iana_identifiers = "Africa/Djibouti" },
    .{ .windows_key = "E. Africa Standard Time", .windows_territory = "ER", .iana_identifiers = "Africa/Asmera" },
    .{ .windows_key = "E. Africa Standard Time", .windows_territory = "ET", .iana_identifiers = "Africa/Addis_Ababa" },
    .{ .windows_key = "E. Africa Standard Time", .windows_territory = "KE", .iana_identifiers = "Africa/Nairobi" },
    .{ .windows_key = "E. Africa Standard Time", .windows_territory = "KM", .iana_identifiers = "Indian/Comoro" },
    .{ .windows_key = "E. Africa Standard Time", .windows_territory = "MG", .iana_identifiers = "Indian/Antananarivo" },
    .{ .windows_key = "E. Africa Standard Time", .windows_territory = "SO", .iana_identifiers = "Africa/Mogadishu" },
    .{ .windows_key = "E. Africa Standard Time", .windows_territory = "TZ", .iana_identifiers = "Africa/Dar_es_Salaam" },
    .{ .windows_key = "E. Africa Standard Time", .windows_territory = "UG", .iana_identifiers = "Africa/Kampala" },
    .{ .windows_key = "E. Africa Standard Time", .windows_territory = "YT", .iana_identifiers = "Indian/Mayotte" },
    .{ .windows_key = "E. Africa Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT-3" },

    // <!-- (UTC+03:30) Tehran -->
    .{ .windows_key = "Iran Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Tehran" },
    .{ .windows_key = "Iran Standard Time", .windows_territory = "IR", .iana_identifiers = "Asia/Tehran" },

    // <!-- (UTC+04:00) Abu Dhabi, Muscat -->
    .{ .windows_key = "Arabian Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Dubai" },
    .{ .windows_key = "Arabian Standard Time", .windows_territory = "AE", .iana_identifiers = "Asia/Dubai" },
    .{ .windows_key = "Arabian Standard Time", .windows_territory = "OM", .iana_identifiers = "Asia/Muscat" },
    .{ .windows_key = "Arabian Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT-4" },

    // <!-- (UTC+04:00) Astrakhan, Ulyanovsk -->
    .{ .windows_key = "Astrakhan Standard Time", .windows_territory = null, .iana_identifiers = "Europe/Astrakhan" },
    .{ .windows_key = "Astrakhan Standard Time", .windows_territory = "RU", .iana_identifiers = "Europe/Astrakhan Europe/Ulyanovsk" },

    // <!-- (UTC+04:00) Baku -->
    .{ .windows_key = "Azerbaijan Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Baku" },
    .{ .windows_key = "Azerbaijan Standard Time", .windows_territory = "AZ", .iana_identifiers = "Asia/Baku" },

    // <!-- (UTC+04:00) Izhevsk, Samara -->
    .{ .windows_key = "Russia Time Zone 3", .windows_territory = null, .iana_identifiers = "Europe/Samara" },
    .{ .windows_key = "Russia Time Zone 3", .windows_territory = "RU", .iana_identifiers = "Europe/Samara" },

    // <!-- (UTC+04:00) Port Louis -->
    .{ .windows_key = "Mauritius Standard Time", .windows_territory = null, .iana_identifiers = "Indian/Mauritius" },
    .{ .windows_key = "Mauritius Standard Time", .windows_territory = "MU", .iana_identifiers = "Indian/Mauritius" },
    .{ .windows_key = "Mauritius Standard Time", .windows_territory = "RE", .iana_identifiers = "Indian/Reunion" },
    .{ .windows_key = "Mauritius Standard Time", .windows_territory = "SC", .iana_identifiers = "Indian/Mahe" },

    // <!-- (UTC+04:00) Saratov -->
    .{ .windows_key = "Saratov Standard Time", .windows_territory = null, .iana_identifiers = "Europe/Saratov" },
    .{ .windows_key = "Saratov Standard Time", .windows_territory = "RU", .iana_identifiers = "Europe/Saratov" },

    // <!-- (UTC+04:00) Tbilisi -->
    .{ .windows_key = "Georgian Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Tbilisi" },
    .{ .windows_key = "Georgian Standard Time", .windows_territory = "GE", .iana_identifiers = "Asia/Tbilisi" },

    // <!-- (UTC+04:00) Volgograd -->
    .{ .windows_key = "Volgograd Standard Time", .windows_territory = null, .iana_identifiers = "Europe/Volgograd" },
    .{ .windows_key = "Volgograd Standard Time", .windows_territory = "RU", .iana_identifiers = "Europe/Volgograd" },

    // <!-- (UTC+04:00) Yerevan -->
    .{ .windows_key = "Caucasus Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Yerevan" },
    .{ .windows_key = "Caucasus Standard Time", .windows_territory = "AM", .iana_identifiers = "Asia/Yerevan" },

    // <!-- (UTC+04:30) Kabul -->
    .{ .windows_key = "Afghanistan Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Kabul" },
    .{ .windows_key = "Afghanistan Standard Time", .windows_territory = "AF", .iana_identifiers = "Asia/Kabul" },

    // <!-- (UTC+05:00) Ashgabat, Tashkent -->
    .{ .windows_key = "West Asia Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Tashkent" },
    .{ .windows_key = "West Asia Standard Time", .windows_territory = "AQ", .iana_identifiers = "Antarctica/Mawson" },
    .{ .windows_key = "West Asia Standard Time", .windows_territory = "KZ", .iana_identifiers = "Asia/Oral Asia/Aqtau Asia/Aqtobe Asia/Atyrau" },
    .{ .windows_key = "West Asia Standard Time", .windows_territory = "MV", .iana_identifiers = "Indian/Maldives" },
    .{ .windows_key = "West Asia Standard Time", .windows_territory = "TF", .iana_identifiers = "Indian/Kerguelen" },
    .{ .windows_key = "West Asia Standard Time", .windows_territory = "TJ", .iana_identifiers = "Asia/Dushanbe" },
    .{ .windows_key = "West Asia Standard Time", .windows_territory = "TM", .iana_identifiers = "Asia/Ashgabat" },
    .{ .windows_key = "West Asia Standard Time", .windows_territory = "UZ", .iana_identifiers = "Asia/Tashkent Asia/Samarkand" },
    .{ .windows_key = "West Asia Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT-5" },

    // <!-- (UTC+05:00) Ekaterinburg -->
    .{ .windows_key = "Ekaterinburg Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Yekaterinburg" },
    .{ .windows_key = "Ekaterinburg Standard Time", .windows_territory = "RU", .iana_identifiers = "Asia/Yekaterinburg" },

    // <!-- (UTC+05:00) Islamabad, Karachi -->
    .{ .windows_key = "Pakistan Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Karachi" },
    .{ .windows_key = "Pakistan Standard Time", .windows_territory = "PK", .iana_identifiers = "Asia/Karachi" },

    // <!-- (UTC+05:00) Qyzylorda -->
    .{ .windows_key = "Qyzylorda Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Qyzylorda" },
    .{ .windows_key = "Qyzylorda Standard Time", .windows_territory = "KZ", .iana_identifiers = "Asia/Qyzylorda" },

    // <!-- (UTC+05:30) Chennai, Kolkata, Mumbai, New Delhi -->
    .{ .windows_key = "India Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Calcutta" },
    .{ .windows_key = "India Standard Time", .windows_territory = "IN", .iana_identifiers = "Asia/Calcutta" },

    // <!-- (UTC+05:30) Sri Jayawardenepura -->
    .{ .windows_key = "Sri Lanka Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Colombo" },
    .{ .windows_key = "Sri Lanka Standard Time", .windows_territory = "LK", .iana_identifiers = "Asia/Colombo" },

    // <!-- (UTC+05:45) Kathmandu -->
    .{ .windows_key = "Nepal Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Katmandu" },
    .{ .windows_key = "Nepal Standard Time", .windows_territory = "NP", .iana_identifiers = "Asia/Katmandu" },

    // <!-- (UTC+06:00) Astana -->
    .{ .windows_key = "Central Asia Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Almaty" },
    .{ .windows_key = "Central Asia Standard Time", .windows_territory = "AQ", .iana_identifiers = "Antarctica/Vostok" },
    .{ .windows_key = "Central Asia Standard Time", .windows_territory = "CN", .iana_identifiers = "Asia/Urumqi" },
    .{ .windows_key = "Central Asia Standard Time", .windows_territory = "IO", .iana_identifiers = "Indian/Chagos" },
    .{ .windows_key = "Central Asia Standard Time", .windows_territory = "KG", .iana_identifiers = "Asia/Bishkek" },
    .{ .windows_key = "Central Asia Standard Time", .windows_territory = "KZ", .iana_identifiers = "Asia/Almaty Asia/Qostanay" },
    .{ .windows_key = "Central Asia Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT-6" },

    // <!-- (UTC+06:00) Dhaka -->
    .{ .windows_key = "Bangladesh Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Dhaka" },
    .{ .windows_key = "Bangladesh Standard Time", .windows_territory = "BD", .iana_identifiers = "Asia/Dhaka" },
    .{ .windows_key = "Bangladesh Standard Time", .windows_territory = "BT", .iana_identifiers = "Asia/Thimphu" },

    // <!-- (UTC+06:00) Omsk -->
    .{ .windows_key = "Omsk Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Omsk" },
    .{ .windows_key = "Omsk Standard Time", .windows_territory = "RU", .iana_identifiers = "Asia/Omsk" },

    // <!-- (UTC+06:30) Yangon (Rangoon) -->
    .{ .windows_key = "Myanmar Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Rangoon" },
    .{ .windows_key = "Myanmar Standard Time", .windows_territory = "CC", .iana_identifiers = "Indian/Cocos" },
    .{ .windows_key = "Myanmar Standard Time", .windows_territory = "MM", .iana_identifiers = "Asia/Rangoon" },

    // <!-- (UTC+07:00) Bangkok, Hanoi, Jakarta -->
    .{ .windows_key = "SE Asia Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Bangkok" },
    .{ .windows_key = "SE Asia Standard Time", .windows_territory = "AQ", .iana_identifiers = "Antarctica/Davis" },
    .{ .windows_key = "SE Asia Standard Time", .windows_territory = "CX", .iana_identifiers = "Indian/Christmas" },
    .{ .windows_key = "SE Asia Standard Time", .windows_territory = "ID", .iana_identifiers = "Asia/Jakarta Asia/Pontianak" },
    .{ .windows_key = "SE Asia Standard Time", .windows_territory = "KH", .iana_identifiers = "Asia/Phnom_Penh" },
    .{ .windows_key = "SE Asia Standard Time", .windows_territory = "LA", .iana_identifiers = "Asia/Vientiane" },
    .{ .windows_key = "SE Asia Standard Time", .windows_territory = "TH", .iana_identifiers = "Asia/Bangkok" },
    .{ .windows_key = "SE Asia Standard Time", .windows_territory = "VN", .iana_identifiers = "Asia/Saigon" },
    .{ .windows_key = "SE Asia Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT-7" },

    // <!-- (UTC+07:00) Barnaul, Gorno-Altaysk -->
    .{ .windows_key = "Altai Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Barnaul" },
    .{ .windows_key = "Altai Standard Time", .windows_territory = "RU", .iana_identifiers = "Asia/Barnaul" },

    // <!-- (UTC+07:00) Hovd -->
    .{ .windows_key = "W. Mongolia Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Hovd" },
    .{ .windows_key = "W. Mongolia Standard Time", .windows_territory = "MN", .iana_identifiers = "Asia/Hovd" },

    // <!-- (UTC+07:00) Krasnoyarsk -->
    .{ .windows_key = "North Asia Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Krasnoyarsk" },
    .{ .windows_key = "North Asia Standard Time", .windows_territory = "RU", .iana_identifiers = "Asia/Krasnoyarsk Asia/Novokuznetsk" },

    // <!-- (UTC+07:00) Novosibirsk -->
    .{ .windows_key = "N. Central Asia Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Novosibirsk" },
    .{ .windows_key = "N. Central Asia Standard Time", .windows_territory = "RU", .iana_identifiers = "Asia/Novosibirsk" },

    // <!-- (UTC+07:00) Tomsk -->
    .{ .windows_key = "Tomsk Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Tomsk" },
    .{ .windows_key = "Tomsk Standard Time", .windows_territory = "RU", .iana_identifiers = "Asia/Tomsk" },

    // <!-- (UTC+08:00) Beijing, Chongqing, Hong Kong, Urumqi -->
    .{ .windows_key = "China Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Shanghai" },
    .{ .windows_key = "China Standard Time", .windows_territory = "CN", .iana_identifiers = "Asia/Shanghai" },
    .{ .windows_key = "China Standard Time", .windows_territory = "HK", .iana_identifiers = "Asia/Hong_Kong" },
    .{ .windows_key = "China Standard Time", .windows_territory = "MO", .iana_identifiers = "Asia/Macau" },

    // <!-- (UTC+08:00) Irkutsk -->
    .{ .windows_key = "North Asia East Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Irkutsk" },
    .{ .windows_key = "North Asia East Standard Time", .windows_territory = "RU", .iana_identifiers = "Asia/Irkutsk" },

    // <!-- (UTC+08:00) Kuala Lumpur, Singapore -->
    .{ .windows_key = "Singapore Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Singapore" },
    .{ .windows_key = "Singapore Standard Time", .windows_territory = "BN", .iana_identifiers = "Asia/Brunei" },
    .{ .windows_key = "Singapore Standard Time", .windows_territory = "ID", .iana_identifiers = "Asia/Makassar" },
    .{ .windows_key = "Singapore Standard Time", .windows_territory = "MY", .iana_identifiers = "Asia/Kuala_Lumpur Asia/Kuching" },
    .{ .windows_key = "Singapore Standard Time", .windows_territory = "PH", .iana_identifiers = "Asia/Manila" },
    .{ .windows_key = "Singapore Standard Time", .windows_territory = "SG", .iana_identifiers = "Asia/Singapore" },
    .{ .windows_key = "Singapore Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT-8" },

    // <!-- (UTC+08:00) Perth -->
    .{ .windows_key = "W. Australia Standard Time", .windows_territory = null, .iana_identifiers = "Australia/Perth" },
    .{ .windows_key = "W. Australia Standard Time", .windows_territory = "AU", .iana_identifiers = "Australia/Perth" },

    // <!-- (UTC+08:00) Taipei -->
    .{ .windows_key = "Taipei Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Taipei" },
    .{ .windows_key = "Taipei Standard Time", .windows_territory = "TW", .iana_identifiers = "Asia/Taipei" },

    // <!-- (UTC+08:00) Ulaanbaatar -->
    .{ .windows_key = "Ulaanbaatar Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Ulaanbaatar" },
    .{ .windows_key = "Ulaanbaatar Standard Time", .windows_territory = "MN", .iana_identifiers = "Asia/Ulaanbaatar Asia/Choibalsan" },

    // <!-- (UTC+08:45) Eucla -->
    .{ .windows_key = "Aus Central W. Standard Time", .windows_territory = null, .iana_identifiers = "Australia/Eucla" },
    .{ .windows_key = "Aus Central W. Standard Time", .windows_territory = "AU", .iana_identifiers = "Australia/Eucla" },

    // <!-- (UTC+09:00) Chita -->
    .{ .windows_key = "Transbaikal Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Chita" },
    .{ .windows_key = "Transbaikal Standard Time", .windows_territory = "RU", .iana_identifiers = "Asia/Chita" },

    // <!-- (UTC+09:00) Osaka, Sapporo, Tokyo -->
    .{ .windows_key = "Tokyo Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Tokyo" },
    .{ .windows_key = "Tokyo Standard Time", .windows_territory = "ID", .iana_identifiers = "Asia/Jayapura" },
    .{ .windows_key = "Tokyo Standard Time", .windows_territory = "JP", .iana_identifiers = "Asia/Tokyo" },
    .{ .windows_key = "Tokyo Standard Time", .windows_territory = "PW", .iana_identifiers = "Pacific/Palau" },
    .{ .windows_key = "Tokyo Standard Time", .windows_territory = "TL", .iana_identifiers = "Asia/Dili" },
    .{ .windows_key = "Tokyo Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT-9" },

    // <!-- (UTC+09:00) Pyongyang -->
    .{ .windows_key = "North Korea Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Pyongyang" },
    .{ .windows_key = "North Korea Standard Time", .windows_territory = "KP", .iana_identifiers = "Asia/Pyongyang" },

    // <!-- (UTC+09:00) Seoul -->
    .{ .windows_key = "Korea Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Seoul" },
    .{ .windows_key = "Korea Standard Time", .windows_territory = "KR", .iana_identifiers = "Asia/Seoul" },

    // <!-- (UTC+09:00) Yakutsk -->
    .{ .windows_key = "Yakutsk Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Yakutsk" },
    .{ .windows_key = "Yakutsk Standard Time", .windows_territory = "RU", .iana_identifiers = "Asia/Yakutsk Asia/Khandyga" },

    // <!-- (UTC+09:30) Adelaide -->
    .{ .windows_key = "Cen. Australia Standard Time", .windows_territory = null, .iana_identifiers = "Australia/Adelaide" },
    .{ .windows_key = "Cen. Australia Standard Time", .windows_territory = "AU", .iana_identifiers = "Australia/Adelaide Australia/Broken_Hill" },

    // <!-- (UTC+09:30) Darwin -->
    .{ .windows_key = "AUS Central Standard Time", .windows_territory = null, .iana_identifiers = "Australia/Darwin" },
    .{ .windows_key = "AUS Central Standard Time", .windows_territory = "AU", .iana_identifiers = "Australia/Darwin" },

    // <!-- (UTC+10:00) Brisbane -->
    .{ .windows_key = "E. Australia Standard Time", .windows_territory = null, .iana_identifiers = "Australia/Brisbane" },
    .{ .windows_key = "E. Australia Standard Time", .windows_territory = "AU", .iana_identifiers = "Australia/Brisbane Australia/Lindeman" },

    // <!-- (UTC+10:00) Canberra, Melbourne, Sydney -->
    .{ .windows_key = "AUS Eastern Standard Time", .windows_territory = null, .iana_identifiers = "Australia/Sydney" },
    .{ .windows_key = "AUS Eastern Standard Time", .windows_territory = "AU", .iana_identifiers = "Australia/Sydney Australia/Melbourne" },

    // <!-- (UTC+10:00) Guam, Port Moresby -->
    .{ .windows_key = "West Pacific Standard Time", .windows_territory = null, .iana_identifiers = "Pacific/Port_Moresby" },
    .{ .windows_key = "West Pacific Standard Time", .windows_territory = "AQ", .iana_identifiers = "Antarctica/DumontDUrville" },
    .{ .windows_key = "West Pacific Standard Time", .windows_territory = "FM", .iana_identifiers = "Pacific/Truk" },
    .{ .windows_key = "West Pacific Standard Time", .windows_territory = "GU", .iana_identifiers = "Pacific/Guam" },
    .{ .windows_key = "West Pacific Standard Time", .windows_territory = "MP", .iana_identifiers = "Pacific/Saipan" },
    .{ .windows_key = "West Pacific Standard Time", .windows_territory = "PG", .iana_identifiers = "Pacific/Port_Moresby" },
    .{ .windows_key = "West Pacific Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT-10" },

    // <!-- (UTC+10:00) Hobart -->
    .{ .windows_key = "Tasmania Standard Time", .windows_territory = null, .iana_identifiers = "Australia/Hobart" },
    .{ .windows_key = "Tasmania Standard Time", .windows_territory = "AU", .iana_identifiers = "Australia/Hobart Australia/Currie Antarctica/Macquarie" },

    // <!-- (UTC+10:00) Vladivostok -->
    .{ .windows_key = "Vladivostok Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Vladivostok" },
    .{ .windows_key = "Vladivostok Standard Time", .windows_territory = "RU", .iana_identifiers = "Asia/Vladivostok Asia/Ust-Nera" },

    // <!-- (UTC+10:30) Lord Howe Island -->
    .{ .windows_key = "Lord Howe Standard Time", .windows_territory = null, .iana_identifiers = "Australia/Lord_Howe" },
    .{ .windows_key = "Lord Howe Standard Time", .windows_territory = "AU", .iana_identifiers = "Australia/Lord_Howe" },

    // <!-- (UTC+11:00) Bougainville Island -->
    .{ .windows_key = "Bougainville Standard Time", .windows_territory = null, .iana_identifiers = "Pacific/Bougainville" },
    .{ .windows_key = "Bougainville Standard Time", .windows_territory = "PG", .iana_identifiers = "Pacific/Bougainville" },

    // <!-- (UTC+11:00) Chokurdakh -->
    .{ .windows_key = "Russia Time Zone 10", .windows_territory = null, .iana_identifiers = "Asia/Srednekolymsk" },
    .{ .windows_key = "Russia Time Zone 10", .windows_territory = "RU", .iana_identifiers = "Asia/Srednekolymsk" },

    // <!-- (UTC+11:00) Magadan -->
    .{ .windows_key = "Magadan Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Magadan" },
    .{ .windows_key = "Magadan Standard Time", .windows_territory = "RU", .iana_identifiers = "Asia/Magadan" },

    // <!-- (UTC+11:00) Norfolk Island -->
    .{ .windows_key = "Norfolk Standard Time", .windows_territory = null, .iana_identifiers = "Pacific/Norfolk" },
    .{ .windows_key = "Norfolk Standard Time", .windows_territory = "NF", .iana_identifiers = "Pacific/Norfolk" },

    // <!-- (UTC+11:00) Sakhalin -->
    .{ .windows_key = "Sakhalin Standard Time", .windows_territory = null, .iana_identifiers = "Asia/Sakhalin" },
    .{ .windows_key = "Sakhalin Standard Time", .windows_territory = "RU", .iana_identifiers = "Asia/Sakhalin" },

    // <!-- (UTC+11:00) Solomon Is., New Caledonia -->
    .{ .windows_key = "Central Pacific Standard Time", .windows_territory = null, .iana_identifiers = "Pacific/Guadalcanal" },
    .{ .windows_key = "Central Pacific Standard Time", .windows_territory = "AQ", .iana_identifiers = "Antarctica/Casey" },
    .{ .windows_key = "Central Pacific Standard Time", .windows_territory = "FM", .iana_identifiers = "Pacific/Ponape Pacific/Kosrae" },
    .{ .windows_key = "Central Pacific Standard Time", .windows_territory = "NC", .iana_identifiers = "Pacific/Noumea" },
    .{ .windows_key = "Central Pacific Standard Time", .windows_territory = "SB", .iana_identifiers = "Pacific/Guadalcanal" },
    .{ .windows_key = "Central Pacific Standard Time", .windows_territory = "VU", .iana_identifiers = "Pacific/Efate" },
    .{ .windows_key = "Central Pacific Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT-11" },

    // <!-- (UTC+12:00) Anadyr, Petropavlovsk-Kamchatsky -->
    .{ .windows_key = "Russia Time Zone 11", .windows_territory = null, .iana_identifiers = "Asia/Kamchatka" },
    .{ .windows_key = "Russia Time Zone 11", .windows_territory = "RU", .iana_identifiers = "Asia/Kamchatka Asia/Anadyr" },

    // <!-- (UTC+12:00) Auckland, Wellington -->
    .{ .windows_key = "New Zealand Standard Time", .windows_territory = null, .iana_identifiers = "Pacific/Auckland" },
    .{ .windows_key = "New Zealand Standard Time", .windows_territory = "AQ", .iana_identifiers = "Antarctica/McMurdo" },
    .{ .windows_key = "New Zealand Standard Time", .windows_territory = "NZ", .iana_identifiers = "Pacific/Auckland" },

    // <!-- (UTC+12:00) Coordinated Universal Time+12 -->
    .{ .windows_key = "UTC+12", .windows_territory = null, .iana_identifiers = "Etc/GMT-12" },
    .{ .windows_key = "UTC+12", .windows_territory = "KI", .iana_identifiers = "Pacific/Tarawa" },
    .{ .windows_key = "UTC+12", .windows_territory = "MH", .iana_identifiers = "Pacific/Majuro Pacific/Kwajalein" },
    .{ .windows_key = "UTC+12", .windows_territory = "NR", .iana_identifiers = "Pacific/Nauru" },
    .{ .windows_key = "UTC+12", .windows_territory = "TV", .iana_identifiers = "Pacific/Funafuti" },
    .{ .windows_key = "UTC+12", .windows_territory = "UM", .iana_identifiers = "Pacific/Wake" },
    .{ .windows_key = "UTC+12", .windows_territory = "WF", .iana_identifiers = "Pacific/Wallis" },
    .{ .windows_key = "UTC+12", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT-12" },

    // <!-- (UTC+12:00) Fiji -->
    .{ .windows_key = "Fiji Standard Time", .windows_territory = null, .iana_identifiers = "Pacific/Fiji" },
    .{ .windows_key = "Fiji Standard Time", .windows_territory = "FJ", .iana_identifiers = "Pacific/Fiji" },

    // <!-- (UTC+12:45) Chatham Islands -->
    .{ .windows_key = "Chatham Islands Standard Time", .windows_territory = null, .iana_identifiers = "Pacific/Chatham" },
    .{ .windows_key = "Chatham Islands Standard Time", .windows_territory = "NZ", .iana_identifiers = "Pacific/Chatham" },

    // <!-- (UTC+13:00) Coordinated Universal Time+13 -->
    .{ .windows_key = "UTC+13", .windows_territory = null, .iana_identifiers = "Etc/GMT-13" },
    .{ .windows_key = "UTC+13", .windows_territory = "KI", .iana_identifiers = "Pacific/Enderbury" },
    .{ .windows_key = "UTC+13", .windows_territory = "TK", .iana_identifiers = "Pacific/Fakaofo" },
    .{ .windows_key = "UTC+13", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT-13" },

    // <!-- (UTC+13:00) Nuku'alofa -->
    .{ .windows_key = "Tonga Standard Time", .windows_territory = null, .iana_identifiers = "Pacific/Tongatapu" },
    .{ .windows_key = "Tonga Standard Time", .windows_territory = "TO", .iana_identifiers = "Pacific/Tongatapu" },

    // <!-- (UTC+13:00) Samoa -->
    .{ .windows_key = "Samoa Standard Time", .windows_territory = null, .iana_identifiers = "Pacific/Apia" },
    .{ .windows_key = "Samoa Standard Time", .windows_territory = "WS", .iana_identifiers = "Pacific/Apia" },

    // <!-- (UTC+14:00) Kiritimati Island -->
    .{ .windows_key = "Line Islands Standard Time", .windows_territory = null, .iana_identifiers = "Pacific/Kiritimati" },
    .{ .windows_key = "Line Islands Standard Time", .windows_territory = "KI", .iana_identifiers = "Pacific/Kiritimati" },
    .{ .windows_key = "Line Islands Standard Time", .windows_territory = "ZZ", .iana_identifiers = "Etc/GMT-14" },
};

const chrono = @import("../../lib.zig");
const std = @import("std");
