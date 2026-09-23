///|
pub(all) struct Syntax {
  component : Char
  element : Char
  decimal : Char
  release : Char
  repetition : Char
  terminator : Char
}

///|
pub(all) struct Segment {
  tag : String
  elements : Array[Array[String]]
  start : Int
  end : Int
}

///|
pub suberror ParseError {
  InvalidAdvice(Int)
  MissingTag(Int)
  UnterminatedSegment(Int)
  TrailingEscape(Int)
}

///|
pub(all) struct Interchange {
  syntax : Syntax
  segments : Array[Segment]
}

///|
/// A structural envelope finding. `segment_index` is zero based.
pub(all) struct EnvelopeIssue {
  code : String
  segment_index : Int
  message : String
}

///|
let default_syntax : Syntax = {
  component: ':',
  element: '+',
  decimal: '.',
  release: '?',
  repetition: ' ',
  terminator: '\'',
}

///|
fn syntax_from(source : StringView) -> (Syntax, Int) raise ParseError {
  if source.length() >= 9 &&
    source.get_char(0).unwrap() == 'U' &&
    source.get_char(1).unwrap() == 'N' &&
    source.get_char(2).unwrap() == 'A' {
    let syntax = {
      component: source.get_char(3).unwrap(),
      element: source.get_char(4).unwrap(),
      decimal: source.get_char(5).unwrap(),
      release: source.get_char(6).unwrap(),
      repetition: source.get_char(7).unwrap(),
      terminator: source.get_char(8).unwrap(),
    }
    if syntax.component == syntax.element ||
      syntax.element == syntax.release ||
      syntax.release == syntax.terminator {
      raise InvalidAdvice(0)
    }
    (syntax, 9)
  } else {
    (default_syntax, 0)
  }
}

///|
fn parse_segment(
  raw : StringView,
  start : Int,
  end : Int,
  syntax : Syntax,
) -> Segment raise ParseError {
  let tag = StringBuilder()
  let elements : Array[Array[String]] = []
  let mut components : Array[String] = []
  let mut value = StringBuilder()
  let mut in_elements = false
  let mut escaped = false
  for c in raw.iter() {
    if escaped {
      if in_elements {
        value.write_char(c)
      } else {
        tag.write_char(c)
      }
      escaped = false
    } else if c == syntax.release {
      escaped = true
    } else if !in_elements && c == syntax.element {
      in_elements = true
    } else if in_elements && c == syntax.element {
      components.push(value.to_string())
      elements.push(components)
      components = []
      value = StringBuilder()
    } else if in_elements && c == syntax.component {
      components.push(value.to_string())
      value = StringBuilder()
    } else if in_elements {
      value.write_char(c)
    } else {
      tag.write_char(c)
    }
  }
  if escaped {
    raise TrailingEscape(end - 1)
  }
  let tag = tag.to_string()
  if tag == "" {
    raise MissingTag(start)
  }
  if in_elements {
    components.push(value.to_string())
    elements.push(components)
  }
  { tag, elements, start, end, }
}

///|
/// Parse one complete UN/EDIFACT interchange from a string.
pub fn parse(source : String) -> Interchange raise ParseError {
  let (syntax, offset) = syntax_from(source[:])
  let segments : Array[Segment] = []
  let mut segment_start = offset
  let mut escaped = false
  let mut i = offset
  while i < source.length() {
    let c = source.get_char(i).unwrap()
    if escaped {
      escaped = false
    } else if c == syntax.release {
      escaped = true
    } else if c == syntax.terminator {
      segments.push(
        parse_segment(source[segment_start:i], segment_start, i + 1, syntax),
      )
      segment_start = i + 1
    }
    i += 1
  }
  if escaped {
    raise TrailingEscape(source.length() - 1)
  }
  if segment_start != source.length() {
    raise UnterminatedSegment(segment_start)
  }
  { syntax, segments, }
}

///|
fn must_release(char : Char, syntax : Syntax) -> Bool {
  char == syntax.component ||
  char == syntax.element ||
  char == syntax.release ||
  char == syntax.repetition ||
  char == syntax.terminator
}

///|
fn write_escaped(
  output : StringBuilder,
  value : String,
  syntax : Syntax,
) -> Unit {
  for char in value {
    if must_release(char, syntax) {
      output.write_char(syntax.release)
    }
    output.write_char(char)
  }
}

///|
/// Serialize an interchange in a deterministic form, including its UNA advice.
pub fn serialize(interchange : Interchange) -> String {
  let output = StringBuilder()
  let syntax = interchange.syntax
  output.write_string("UNA")
  output.write_char(syntax.component)
  output.write_char(syntax.element)
  output.write_char(syntax.decimal)
  output.write_char(syntax.release)
  output.write_char(syntax.repetition)
  output.write_char(syntax.terminator)
  for segment in interchange.segments {
    output.write_string(segment.tag)
    for element in segment.elements {
      output.write_char(syntax.element)
      let mut index = 0
      while index < element.length() {
        if index > 0 {
          output.write_char(syntax.component)
        }
        write_escaped(output, element[index], syntax)
        index += 1
      }
    }
    output.write_char(syntax.terminator)
  }
  output.to_string()
}

///|
fn first_value(segment : Segment, index : Int) -> String? {
  if index < segment.elements.length() && segment.elements[index].length() > 0 {
    Some(segment.elements[index][0])
  } else {
    None
  }
}

///|
/// Check service-segment pairing and control references at the syntax layer.
pub fn validate_envelope(interchange : Interchange) -> Array[EnvelopeIssue] {
  let issues : Array[EnvelopeIssue] = []
  let segments = interchange.segments
  if segments.length() == 0 {
    issues.push({
      code: "empty",
      segment_index: 0,
      message: "interchange has no segments",
    })
    return issues
  }
  if segments[0].tag != "UNB" {
    issues.push({
      code: "missing-unb",
      segment_index: 0,
      message: "interchange must start with UNB",
    })
  }
  if segments[segments.length() - 1].tag != "UNZ" {
    issues.push({
      code: "missing-unz",
      segment_index: segments.length() - 1,
      message: "interchange must end with UNZ",
    })
  }
  let interchange_reference = if segments[0].tag == "UNB" {
    first_value(segments[0], 4)
  } else {
    None
  }
  let mut open_message : (Int, String)? = None
  let mut i = 0
  while i < segments.length() {
    let segment = segments[i]
    if segment.tag == "UNH" {
      match open_message {
        Some(_) =>
          issues.push({
            code: "nested-unh",
            segment_index: i,
            message: "UNH appears before the previous UNT",
          })
        None =>
          match first_value(segment, 0) {
            Some(value) => open_message = Some((i, value))
            None =>
              issues.push({
                code: "missing-unh-reference",
                segment_index: i,
                message: "UNH has no message reference",
              })
          }
      }
    } else if segment.tag == "UNT" {
      match open_message {
        None =>
          issues.push({
            code: "orphan-unt",
            segment_index: i,
            message: "UNT has no matching UNH",
          })
        Some((open_index, reference)) => {
          let actual_count = i - open_index + 1
          match first_value(segment, 0) {
            Some(value) =>
              if value != actual_count.to_string() {
                issues.push({
                  code: "message-count",
                  segment_index: i,
                  message: "UNT segment count does not match the message",
                })
              }
            None =>
              issues.push({
                code: "missing-unt-count",
                segment_index: i,
                message: "UNT has no segment count",
              })
          }
          match first_value(segment, 1) {
            Some(value) =>
              if value != reference {
                issues.push({
                  code: "message-reference",
                  segment_index: i,
                  message: "UNT reference does not match UNH",
                })
              }
            None =>
              issues.push({
                code: "missing-unt-reference",
                segment_index: i,
                message: "UNT has no message reference",
              })
          }
          open_message = None
        }
      }
    }
    i += 1
  }
  match open_message {
    Some((index, _)) =>
      issues.push({
        code: "missing-unt",
        segment_index: index,
        message: "message has no closing UNT",
      })
    None => ()
  }
  if segments[segments.length() - 1].tag == "UNZ" {
    match interchange_reference {
      Some(reference) =>
        match first_value(segments[segments.length() - 1], 1) {
          Some(value) =>
            if value != reference {
              issues.push({
                code: "interchange-reference",
                segment_index: segments.length() - 1,
                message: "UNZ reference does not match UNB",
              })
            }
          None =>
            issues.push({
              code: "missing-unz-reference",
              segment_index: segments.length() - 1,
              message: "UNZ has no interchange reference",
            })
        }
      None => ()
    }
  }
  issues
}
