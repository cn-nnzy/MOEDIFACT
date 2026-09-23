///|
/// Incremental parser for interchanges split across arbitrary text chunks.
pub struct StreamParser {
  priv mut syntax : Syntax?
  priv mut pending : StringBuilder
  priv mut segment : StringBuilder
  priv segments : Array[Segment]
  priv mut segment_start : Int
  priv mut offset : Int
  priv mut escaped : Bool
  priv mut finished : Bool
}

///|
/// Create an empty incremental parser.
pub fn StreamParser::new() -> StreamParser {
  {
    syntax: None,
    pending: StringBuilder(),
    segment: StringBuilder(),
    segments: [],
    segment_start: 0,
    offset: 0,
    escaped: false,
    finished: false,
  }
}

///|
fn StreamParser::process(
  self : StreamParser,
  text : String,
  start : Int,
) -> Unit raise ParseError {
  let syntax = self.syntax.unwrap()
  let mut i = start
  while i < text.length() {
    let char = text.get_char(i).unwrap()
    if self.escaped {
      self.segment.write_char(char)
      self.escaped = false
    } else if char == syntax.release {
      self.segment.write_char(char)
      self.escaped = true
    } else if char == syntax.terminator {
      self.segments.push(
        parse_segment(
          self.segment.to_string()[:],
          self.segment_start,
          self.offset + 1,
          syntax,
        ),
      )
      self.segment = StringBuilder()
      self.segment_start = self.offset + 1
    } else {
      self.segment.write_char(char)
    }
    self.offset += 1
    i += 1
  }
}

///|
fn StreamParser::initialize(
  self : StreamParser,
  force : Bool,
) -> Unit raise ParseError {
  if self.syntax is Some(_) {
    return
  }
  let buffered = self.pending.to_string()
  if !force && buffered.length() < 3 {
    return
  }
  let has_advice = buffered.length() >= 3 &&
    buffered.get_char(0).unwrap() == 'U' &&
    buffered.get_char(1).unwrap() == 'N' &&
    buffered.get_char(2).unwrap() == 'A'
  if has_advice && buffered.length() < 9 && !force {
    return
  }
  let (syntax, start) = syntax_from(buffered[:])
  self.syntax = Some(syntax)
  self.offset = start
  self.segment_start = start
  self.pending = StringBuilder()
  self.process(buffered, start)
}

///|
/// Consume another chunk. Separators and release pairs may cross chunk boundaries.
pub fn StreamParser::feed(
  self : StreamParser,
  chunk : String,
) -> Unit raise ParseError {
  if self.finished {
    raise StreamAlreadyFinished
  }
  if self.syntax is None {
    self.pending.write_string(chunk)
    self.initialize(false)
  } else {
    self.process(chunk, 0)
  }
}

///|
/// Finish the stream and return the parsed interchange.
pub fn StreamParser::finish(
  self : StreamParser,
) -> Interchange raise ParseError {
  if self.finished {
    raise StreamAlreadyFinished
  }
  self.initialize(true)
  self.finished = true
  if self.escaped {
    raise TrailingEscape(self.offset - 1)
  }
  if self.segment.to_string() != "" {
    raise UnterminatedSegment(self.segment_start)
  }
  { syntax: self.syntax.unwrap_or(default_syntax), segments: self.segments, }
}
