import js from '@eslint/js'
import query from '@tanstack/eslint-plugin-query'
import prettier from 'eslint-config-prettier/flat'
import hooks from 'eslint-plugin-react-hooks'
import { defineConfig, globalIgnores } from 'eslint/config'
import globals from 'globals'
import tseslint from 'typescript-eslint'

export default defineConfig(
  globalIgnores(['dist/**', 'src/client/**']),
  {
    extends: [js.configs.recommended],
    files: ['**/*.{js,mjs}'],
    languageOptions: { globals: globals.node },
  },
  {
    extends: [js.configs.recommended, tseslint.configs.recommended],
    files: ['**/*.{ts,tsx}'],
    languageOptions: { parserOptions: { jsxPragma: null } },
    plugins: { '@tanstack/query': query, 'react-hooks': hooks },
    rules: {
      '@tanstack/query/exhaustive-deps': 'error',
      '@tanstack/query/no-unstable-deps': 'error',
      '@tanstack/query/stable-query-client': 'error',
      'react-hooks/exhaustive-deps': 'error',
      'react-hooks/rules-of-hooks': 'error',
    },
  },
  {
    files: ['src/**/*.{ts,tsx}', 'tests/**/*.{ts,tsx}', 'worker/**/*.ts'],
    languageOptions: {
      parserOptions: {
        project: ['./tsconfig.json', './tsconfig.tests.json', './tsconfig.worker.json'],
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      '@tanstack/query/no-void-query-fn': 'error',
      '@typescript-eslint/await-thenable': 'error',
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': 'error',
    },
  },
  prettier,
)
