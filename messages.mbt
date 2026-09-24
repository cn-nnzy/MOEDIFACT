///|
/// Index messages after validating the interchange service envelope.
/// `end_index` is exclusive, so each span includes its UNH and UNT segments.
pub fn index_messages(
  interchange : Interchange,
) -> Array[MessageSpan] raise MessageIndexError {
  let issues = validate_envelope(interchange)
  if issues.length() > 0 {
    raise InvalidEnvelope(issues[0].code, issues[0].segment_index)
  }
  let spans : Array[MessageSpan] = []
  let mut group_reference : String? = None
  let mut message_start = 0
  let mut message_reference = ""
  let mut message_type = ""
  let mut message_group : String? = None
  let mut i = 0
  while i < interchange.segments.length() {
    let segment = interchange.segments[i]
    if segment.tag == "UNG" {
      group_reference = first_value(segment, 4)
    } else if segment.tag == "UNE" {
      group_reference = None
    } else if segment.tag == "UNH" {
      message_start = i
      message_reference = first_value(segment, 0).unwrap_or("")
      message_type = match first_value(segment, 1) {
        Some(value) if value != "" => value
        _ => raise MissingMessageType(i)
      }
      message_group = group_reference
    } else if segment.tag == "UNT" {
      spans.push({
        start_index: message_start,
        end_index: i + 1,
        reference: message_reference,
        message_type,
        group_reference: message_group,
      })
    }
    i += 1
  }
  spans
}
