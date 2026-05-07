export function decodePolyline(encoded) {
  if (!encoded) return [];

  const coordinates = [];
  let index = 0;
  let latitude = 0;
  let longitude = 0;

  while (index < encoded.length) {
    const latResult = decodeValue(encoded, index);
    latitude += latResult.value;
    index = latResult.nextIndex;

    const lngResult = decodeValue(encoded, index);
    longitude += lngResult.value;
    index = lngResult.nextIndex;

    coordinates.push({
      latitude: latitude / 1e5,
      longitude: longitude / 1e5
    });
  }

  return coordinates;
}

function decodeValue(encoded, startIndex) {
  let result = 0;
  let shift = 0;
  let index = startIndex;
  let byte = null;

  do {
    byte = encoded.charCodeAt(index) - 63;
    index += 1;
    result |= (byte & 0x1f) << shift;
    shift += 5;
  } while (byte >= 0x20 && index <= encoded.length);

  return {
    value: (result & 1) ? ~(result >> 1) : (result >> 1),
    nextIndex: index
  };
}
