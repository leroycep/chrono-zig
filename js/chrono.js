
export default function getChronoEnv(getGlobalInstance) {
    const getMem = () => getGlobalInstance().exports.memory.buffer;
    return {
        getOffset(timestampMsInPtr, offsetOutPtr) {
            const timestamp_ms = new BigInt64Array(getMem(), timestampMsInPtr, 1);
            const offset_seconds = new BigInt64Array(getMem(), offsetOutPtr, 1);

            const date = new Date(Number(timestamp_ms[0]));
            offset_seconds[0] = BigInt(date.getTimezoneOffset());
        }
    };
}
