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
