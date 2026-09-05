import { createRequire } from 'node:module'

const require = createRequire(new URL('./web/package.json', import.meta.url))

export default {
  importOrder: [
    '^preact(?:/.*)?$',
    '',
    '<BUILTIN_MODULES>',
    '<THIRD_PARTY_MODULES>',
    '',
    '^(?!.*\\.css(?:\\.ts)?$)@/',
    '',
    '^(?!.*\\.css(?:\\.ts)?$)\\.',
    '',
    '\\.css(?:\\.ts)?$',
  ],
  importOrderSafeSideEffects: ['^@/styles\\.css$'],
  importOrderTypeScriptVersion: '7.0.2',
  overrides: [
    {
      files: '*.sql',
      options: {
        parser: 'postgresql',
        sqlCanonicalSyntax: false,
        sqlParamTypes: ['@name', '$nr'],
        sqlTypeCase: 'lower',
      },
    },
  ],
  plugins: [
    '@ianvs/prettier-plugin-sort-imports',
    'prettier-plugin-sql-cst',
    'prettier-plugin-yaml',
  ].map((plugin) => require.resolve(plugin)),
  printWidth: 100,
  proseWrap: 'always',
  semi: false,
  singleQuote: true,
  trailingComma: 'all',
  yamlCollectionStyle: 'block',
}
