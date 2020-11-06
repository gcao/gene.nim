# Gene - a general purpose language written in Nim

## Credit

The parser and basic data types are built on top of [EDN Parser](https://github.com/rosado/edn.nim) that is
created by Roland Sadowski.

## Notes

* Build

```
nimble build
```

* Run interactive Gene interpreter (after building the executable)

```
./gene
```

* Run all tests

```
nimble test
```

* Run specific test file

```
nim c -r tests/test_parser.nim
```
