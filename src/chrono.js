export default function getChronoEnv(getInstanceExports) {
  const getMem = () => getInstanceExports().memory.buffer;
  return {
    getOffset(timestampMsInPtr, offsetOutPtr) {
      const timestamp_ms = new BigInt64Array(getMem(), timestampMsInPtr, 1);
      const offset_seconds = new BigInt64Array(getMem(), offsetOutPtr, 1);

      const date = new Date(Number(timestamp_ms[0]));
      offset_seconds[0] = BigInt(-date.getTimezoneOffset()) * BigInt(60);
    },
    datetimeStrToUTCTimestamp(localDateTimePtr, localDateTimeLen) {
      const text_decoder = new TextDecoder();
      const localDateTimeStr = text_decoder.decode(
        new Uint8Array(getMem(), localDateTimePtr, localDateTimeLen)
      );

      const localDateTime = new Date(localDateTimeStr);
      return BigInt(localDateTime.getTime()) / 1000n;
    },
  };
}
