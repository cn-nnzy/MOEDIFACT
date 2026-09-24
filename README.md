# MOEDIFACT

Lossless syntax handling for UN/EDIFACT interchanges.

The first slice focuses on the ISO 9735 syntax layer: service string advice,
escaped separators, segments, elements, and precise source offsets. It does
not attempt to interpret a particular message directory such as ORDERS or
INVOIC.

```moonbit
let interchange = @moedifact.parse("UNA:+.? 'UNB+UNOC:3+SENDER+RECEIVER'")
let canonical = @moedifact.serialize(interchange)

let bounded = @moedifact.parse_with_limits(
  canonical,
  { max_input_units: 1048576, max_segments: 10000, max_segment_units: 65536 },
)

let stream = @moedifact.StreamParser::new()
stream.feed("UNA:+.?")
stream.feed(" 'UNB+UNOC:3+SENDER+RECEIVER'")
let streamed = stream.finish()

let guarded_stream = @moedifact.StreamParser::new_with_limits({
  max_input_units: 1048576,
  max_segments: 10000,
  max_segment_units: 65536,
})
guarded_stream.feed("UNB+UNOC:3+SENDER+RECEIVER+DATE+1'")
guarded_stream.feed("UNZ+0+1'")
let guarded = guarded_stream.finish()

let complete = @moedifact.parse(
  "UNB+UNOC:3+S+R+DATE+42'UNH+1+INVOIC:D:96A:UN'UNT+2+1'UNZ+1+42'",
)
let messages = @moedifact.index_messages(complete)
for message in messages {
  // Message segments occupy [start_index, end_index) in complete.segments.
  println(message.message_type)
}
```

The package is designed for import gates and offline validation tools. A
directory-level message validator can build on this syntax tree later.

## Status

The library currently provides batch and incremental parsing, resource limits
for both input modes, deterministic serialization, release character handling,
service-envelope checks, and indexing of validated messages. Message directory
validation is a planned follow-up slice.

## License

Apache-2.0
