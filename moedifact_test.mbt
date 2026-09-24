///|
test "parses service advice and escaped separators" {
  let parsed = @moedifact.parse(
    "UNA:+.? 'UNB+SENDER:MAIN+RECEIVER'FTX+hello?+world'",
  )
  assert_eq(parsed.syntax.component, ':')
  assert_eq(parsed.syntax.release, '?')
  assert_eq(parsed.segments.length(), 2)
  assert_eq(parsed.segments[0].tag, "UNB")
  assert_eq(parsed.segments[0].elements[0][1], "MAIN")
  assert_eq(parsed.segments[1].elements[0][0], "hello+world")
}

///|
test "keeps every released syntax character as data" {
  let parsed = @moedifact.parse(
    "UNA:+.? 'FTX+left?:right+say?+more+ask??again+close?'later'",
  )
  let elements = parsed.segments[0].elements
  assert_eq(elements[0][0], "left:right")
  assert_eq(elements[1][0], "say+more")
  assert_eq(elements[2][0], "ask?again")
  assert_eq(elements[3][0], "close'later")
}

///|
test "serializes released data deterministically" {
  let source = "UNA:+.? 'FTX+left?:right+say?+more+ask??again+close?'later'"
  let encoded = @moedifact.serialize(@moedifact.parse(source))
  assert_eq(encoded, source)
  let reparsed = @moedifact.parse(encoded)
  assert_eq(reparsed.segments[0].elements[0][0], "left:right")
  assert_eq(reparsed.segments[0].elements[3][0], "close'later")
}

///|
test "reports an unterminated segment" {
  try @moedifact.parse("UNB+SENDER") catch {
    _ => ()
  } noraise {
    _ => fail("expected parse error")
  }
}

///|
test "validates message and interchange envelopes" {
  let valid = @moedifact.parse(
    "UNB+UNOC:3+SENDER+RECEIVER+DATE+42'UNH+1+ORDERS:D:96A:UN'BGM+220'UNT+3+1'UNZ+1+42'",
  )
  assert_eq(@moedifact.validate_envelope(valid).length(), 0)
  let invalid = @moedifact.parse(
    "UNB+UNOC:3+SENDER+RECEIVER+DATE+42'UNH+1+ORDERS:D:96A:UN'BGM+220'UNT+4+9'UNZ+1+7'",
  )
  let findings = @moedifact.validate_envelope(invalid)
  assert_eq(findings.length(), 3)
  assert_eq(findings[0].code, "message-count")
}

///|
test "checks the UNZ message total" {
  let valid = @moedifact.parse(
    "UNB+UNOC:3+S+R+DATE+42'UNH+1+ORDERS:D:96A:UN'UNT+2+1'UNH+2+INVOIC:D:96A:UN'UNT+2+2'UNZ+2+42'",
  )
  assert_eq(@moedifact.validate_envelope(valid).length(), 0)
  let wrong_total = @moedifact.parse(
    "UNB+UNOC:3+S+R+DATE+42'UNH+1+ORDERS:D:96A:UN'UNT+2+1'UNH+2+INVOIC:D:96A:UN'UNT+2+2'UNZ+1+42'",
  )
  let findings = @moedifact.validate_envelope(wrong_total)
  assert_eq(findings.length(), 1)
  assert_eq(findings[0].code, "interchange-count")
}

///|
test "reports a missing UNB control reference" {
  let parsed = @moedifact.parse("UNB+UNOC:3+S+R+DATE'UNZ+0'")
  let findings = @moedifact.validate_envelope(parsed)
  assert_eq(findings.length(), 1)
  assert_eq(findings[0].code, "missing-unb-reference")
}

///|
test "validates functional group envelopes" {
  let valid = @moedifact.parse(
    "UNB+UNOC:3+S+R+DATE+42'UNG+ORDERS+S+R+DATE+G1'UNH+1+ORDERS:D:96A:UN'UNT+2+1'UNH+2+ORDERS:D:96A:UN'UNT+2+2'UNE+2+G1'UNZ+1+42'",
  )
  assert_eq(@moedifact.validate_envelope(valid).length(), 0)
  let invalid = @moedifact.parse(
    "UNB+UNOC:3+S+R+DATE+42'UNG+ORDERS+S+R+DATE+G1'UNH+1+ORDERS:D:96A:UN'UNT+2+1'UNH+2+ORDERS:D:96A:UN'UNT+2+2'UNE+1+G2'UNZ+1+42'",
  )
  let findings = @moedifact.validate_envelope(invalid)
  assert_eq(findings.length(), 2)
  assert_eq(findings[0].code, "group-count")
  assert_eq(findings[1].code, "group-reference")
}

///|
test "reports an unclosed functional group" {
  let parsed = @moedifact.parse(
    "UNB+UNOC:3+S+R+DATE+42'UNG+ORDERS+S+R+DATE+G1'UNH+1+ORDERS:D:96A:UN'UNT+2+1'UNZ+1+42'",
  )
  let findings = @moedifact.validate_envelope(parsed)
  assert_eq(findings.length(), 2)
  assert_eq(findings[0].code, "missing-une")
  assert_eq(findings[1].code, "interchange-count")
}

///|
test "accepts input exactly at configured limits" {
  let source = "UNA:+.? 'UNB+S+R+D+1'UNZ+0+1'"
  let parsed = @moedifact.parse_with_limits(source, {
    max_input_units: source.length(),
    max_segments: 2,
    max_segment_units: 12,
  })
  assert_eq(parsed.segments.length(), 2)
}

///|
test "rejects bounded parsing overflows" {
  let source = "UNB+S+R+D+1'UNZ+0+1'"
  try
    @moedifact.parse_with_limits(source, {
      max_input_units: source.length() - 1,
      max_segments: 2,
      max_segment_units: 12,
    })
  catch {
    _ => ()
  } noraise {
    _ => fail("expected input limit error")
  }
  try
    @moedifact.parse_with_limits(source, {
      max_input_units: source.length(),
      max_segments: 1,
      max_segment_units: 12,
    })
  catch {
    _ => ()
  } noraise {
    _ => fail("expected segment count error")
  }
  try
    @moedifact.parse_with_limits(source, {
      max_input_units: source.length(),
      max_segments: 2,
      max_segment_units: 8,
    })
  catch {
    _ => ()
  } noraise {
    _ => fail("expected segment length error")
  }
}

///|
test "parses arbitrary stream chunk boundaries" {
  let parser = @moedifact.StreamParser::new()
  parser.feed("U")
  parser.feed("NA:")
  parser.feed("+.?")
  parser.feed(" '")
  parser.feed("UNB+S?")
  parser.feed("+R+R+D+1'FTX+close?")
  parser.feed("'later'UNZ+0+1")
  parser.feed("'")
  let streamed = parser.finish()
  let batch = @moedifact.parse(
    "UNA:+.? 'UNB+S?+R+R+D+1'FTX+close?'later'UNZ+0+1'",
  )
  assert_eq(@moedifact.serialize(streamed), @moedifact.serialize(batch))
  assert_eq(streamed.segments[0].elements[0][0], "S+R")
  assert_eq(streamed.segments[1].elements[0][0], "close'later")
}

///|
test "rejects an unfinished stream segment" {
  let parser = @moedifact.StreamParser::new()
  parser.feed("UNB+SENDER")
  try parser.finish() catch {
    _ => ()
  } noraise {
    _ => fail("expected unfinished segment error")
  }
}

///|
test "enforces stream limits across chunk boundaries" {
  let source = "UNA:+.? 'UNB+S+R+D+1'UNZ+0+1'"
  let exact = @moedifact.StreamParser::new_with_limits({
    max_input_units: source.length(),
    max_segments: 2,
    max_segment_units: 12,
  })
  exact.feed("UNA:+.?")
  exact.feed(" 'UNB+S+")
  exact.feed("R+D+1'UNZ+")
  exact.feed("0+1'")
  assert_eq(exact.finish().segments.length(), 2)
  let input_limited = @moedifact.StreamParser::new_with_limits({
    max_input_units: source.length() - 1,
    max_segments: 2,
    max_segment_units: 12,
  })
  input_limited.feed("UNA:+.? 'UNB+S+R+D+1'")
  try input_limited.feed("UNZ+0+1'") catch {
    @moedifact.InputLimitExceeded(actual, limit) => {
      assert_eq(actual, source.length())
      assert_eq(limit, source.length() - 1)
    }
    _ => fail("expected input limit error")
  } noraise {
    _ => fail("expected input limit error")
  }
  let segment_limited = @moedifact.StreamParser::new_with_limits({
    max_input_units: source.length(),
    max_segments: 2,
    max_segment_units: 8,
  })
  segment_limited.feed("UNB+S+")
  try segment_limited.feed("R+D+") catch {
    @moedifact.SegmentLengthLimitExceeded(index, actual, limit) => {
      assert_eq(index, 0)
      assert_eq(actual, 9)
      assert_eq(limit, 8)
    }
    _ => fail("expected segment length error")
  } noraise {
    _ => fail("expected segment length error")
  }
  let count_limited = @moedifact.StreamParser::new_with_limits({
    max_input_units: source.length(),
    max_segments: 1,
    max_segment_units: 12,
  })
  count_limited.feed("UNB+S+R+D+1'UNZ+0+")
  try count_limited.feed("1'") catch {
    @moedifact.SegmentLimitExceeded(actual, limit) => {
      assert_eq(actual, 2)
      assert_eq(limit, 1)
    }
    _ => fail("expected segment count error")
  } noraise {
    _ => fail("expected segment count error")
  }
}

///|
test "indexes grouped messages with segment ranges" {
  let interchange = @moedifact.parse(
    "UNB+UNOC:3+S+R+DATE+42'UNG+ORDERS+S+R+DATE+G1'UNH+A+ORDERS:D:96A:UN'BGM+220'UNT+3+A'UNH+B+ORDERS:D:96A:UN'UNT+2+B'UNE+2+G1'UNZ+1+42'",
  )
  let spans = @moedifact.index_messages(interchange)
  assert_eq(spans.length(), 2)
  assert_eq(spans[0].start_index, 2)
  assert_eq(spans[0].end_index, 5)
  assert_eq(spans[0].reference, "A")
  assert_eq(spans[0].message_type, "ORDERS")
  assert_eq(spans[0].group_reference, Some("G1"))
  assert_eq(interchange.segments[spans[0].end_index - 1].tag, "UNT")
  assert_eq(spans[1].start_index, 5)
  assert_eq(spans[1].end_index, 7)
  assert_eq(spans[1].reference, "B")
}

///|
test "indexes an ungrouped message and rejects a broken envelope" {
  let interchange = @moedifact.parse(
    "UNB+UNOC:3+S+R+DATE+42'UNH+1+INVOIC:D:96A:UN'UNT+2+1'UNZ+1+42'",
  )
  let spans = @moedifact.index_messages(interchange)
  assert_eq(spans.length(), 1)
  assert_eq(spans[0].group_reference, None)
  assert_eq(spans[0].message_type, "INVOIC")
  let broken = @moedifact.parse(
    "UNB+UNOC:3+S+R+DATE+42'UNH+1+INVOIC:D:96A:UN'UNT+3+1'UNZ+1+42'",
  )
  try @moedifact.index_messages(broken) catch {
    @moedifact.InvalidEnvelope(code, index) => {
      assert_eq(code, "message-count")
      assert_eq(index, 2)
    }
    _ => fail("expected envelope error")
  } noraise {
    _ => fail("expected envelope error")
  }
}

///|
test "requires a message type before indexing" {
  let interchange = @moedifact.parse(
    "UNB+UNOC:3+S+R+DATE+42'UNH+1'UNT+2+1'UNZ+1+42'",
  )
  try @moedifact.index_messages(interchange) catch {
    @moedifact.MissingMessageType(index) => assert_eq(index, 1)
    _ => fail("expected missing message type")
  } noraise {
    _ => fail("expected missing message type")
  }
}

///|
test "rejects incomplete and conflicting service advice" {
  for malformed in ["UNA:+.?", "UNA:+:? 'UNB+S'", "UNA:+.??'UNB+S'"] {
    try @moedifact.parse(malformed) catch {
      @moedifact.InvalidAdvice(index) => assert_eq(index, 0)
      _ => fail("expected invalid service advice")
    } noraise {
      _ => fail("expected invalid service advice")
    }
  }
  let parser = @moedifact.StreamParser::new()
  parser.feed("UN")
  parser.feed("A:+.?")
  try parser.finish() catch {
    @moedifact.InvalidAdvice(index) => assert_eq(index, 0)
    _ => fail("expected invalid service advice")
  } noraise {
    _ => fail("expected invalid service advice")
  }
  let conflicting = @moedifact.StreamParser::new()
  conflicting.feed("UNA:+:")
  try conflicting.feed("? 'UNB+S'") catch {
    @moedifact.InvalidAdvice(index) => assert_eq(index, 0)
    _ => fail("expected conflicting service advice")
  } noraise {
    _ => fail("expected conflicting service advice")
  }
}

///|
test "preserves released segment tags when serializing" {
  let source = "UNA:+.? 'F?+O+say?'again'"
  let parsed = @moedifact.parse(source)
  assert_eq(parsed.segments[0].tag, "F+O")
  assert_eq(@moedifact.serialize(parsed), source)
  let streamed = @moedifact.StreamParser::new()
  streamed.feed("UNA:+.? 'F?")
  streamed.feed("+O+say?")
  streamed.feed("'again'")
  assert_eq(@moedifact.serialize(streamed.finish()), source)
}
