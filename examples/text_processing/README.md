# Text Processing

https://github.com/gcao/gene.nim/issues/9

```
cat examples/text_processing/test.csv | gene --im csv --pr --eval '(v .@1)'

cat examples/text_processing/test.csv | gene --im csv --pr --fr --eval '(if (i < 5) (v .@1))'
```
