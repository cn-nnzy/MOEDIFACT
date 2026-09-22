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
  let fields : Array[String] = []
  let mut current = StringBuilder()
  let mut escaped = false
  for c in raw.iter() {
    if escaped {
      current.write_char(c)
      escaped = false
    } else if c == syntax.release {
      escaped = true
    } else if c == syntax.element {
      fields.push(current.to_string())
      current = StringBuilder()
    } else {
      current.write_char(c)
    }
  }
  if escaped {
    raise TrailingEscape(end - 1)
  }
  fields.push(current.to_string())
  if fields.length() == 0 || fields[0] == "" {
    raise MissingTag(start)
  }
  let elements : Array[Array[String]] = []
  for field in fields[1:] {
    let parts : Array[String] = []
    let mut component = StringBuilder()
    let mut escaped_component = false
    for c in field.iter() {
      if escaped_component {
        component.write_char(c)
        escaped_component = false
      } else if c == syntax.release {
        escaped_component = true
      } else if c == syntax.component {
        parts.push(component.to_string())
        component = StringBuilder()
      } else {
        component.write_char(c)
      }
    }
    if escaped_component {
      raise TrailingEscape(end - 1)
    }
    parts.push(component.to_string())
    elements.push(parts)
  }
  { tag: fields[0], elements, start, end, }
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
