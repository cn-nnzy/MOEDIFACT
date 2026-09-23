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
  try {
    ignore(@moedifact.parse("UNB+SENDER"))
    fail("expected parse error")
  } catch {
    _ => ()
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
