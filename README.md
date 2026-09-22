# MOEDIFACT

Lossless syntax handling for UN/EDIFACT interchanges.

The first slice focuses on the ISO 9735 syntax layer: service string advice,
escaped separators, segments, elements, and precise source offsets. It does
not attempt to interpret a particular message directory such as ORDERS or
INVOIC.

```moonbit
let interchange = @moedifact.parse("UNA:+.? 'UNB+UNOC:3+SENDER+RECEIVER'" )
```

The package is designed for import gates and offline validation tools. A
directory-level message validator can build on this syntax tree later.

## Status

The parser and its error model are the initial public slice. Envelope counts,
streaming input, and deterministic serialization are planned follow-up slices.

## License

Apache-2.0
