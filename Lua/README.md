## My Luau code commenting & variable naming quirks
This section is mostly for those who are here to read my scripts. <br>
After a long time of indecisiveness and a lot of variations in how I visually structure my code, these are the habits I've settled on: <br>
- I always use the `--!strict` type [inference mode](https://create.roblox.com/docs/luau/type-checking#inference-modes) and I make use of Luau's type features <br>
- I separate sections of code with `-- / Section /`, for example `-- / Services /` or `--/ Variables /` <br>
- I try to name my functions as VerbNoun(...) or similar <br>
- I tend to use longer, more descriptive variable names over shorter names (but when doing math-heavy sections I usually use short names for convenience) <br>
- I add a lot of comments to my code, both formal and informal, in case someone ever reads it <br>
- My naming convention for variables is (usually) as follows:

| Case style | Usage |
| --- | --- |
| SCREAMING_SNAKE_CASE | Settings |
| PascalCase | Global variables |
| camelCase | Scoped variables |
