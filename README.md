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
```

The package is designed for import gates and offline validation tools. A
directory-level message validator can build on this syntax tree later.

## Status

The library currently provides parsing with optional resource limits,
deterministic serialization, release character handling, and service-envelope
checks. Streaming input and message directory validation are planned follow-up
slices.

## License

Apache-2.0
