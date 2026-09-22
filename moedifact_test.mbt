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
test "reports an unterminated segment" {
  try {
    ignore(@moedifact.parse("UNB+SENDER"))
    fail("expected parse error")
  } catch {
    _ => ()
  }
}
