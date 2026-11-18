Reload shell and initiate

source ~/.bashrc
cargo new faers-rust


Build
```
cargo lambda build --release --arm64 --output-format zip
```

run lambda

```
aws lambda invoke --function-name v1-faers-rust-lambda-dev --cli-binary-format raw-in-base64-out --payload '{"limit": 5, "skip": 0}' response.json