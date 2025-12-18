# Used by "mix format"
[
  plugins: [Spark.Formatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: [
    handle: 2
  ],
  export: [
    locals_without_parens: [
      handle: 2
    ]
  ]
]
