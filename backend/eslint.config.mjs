// @ts-check
import js from '@eslint/js';
import tsParser from '@typescript-eslint/parser';
import tsPlugin from '@typescript-eslint/eslint-plugin';
import prettier from 'eslint-config-prettier';

/** @type {import('eslint').Linter.Config[]} */
export default [
  js.configs.recommended,
  {
    files: ['src/**/*.ts', 'test/**/*.ts', 'prisma/**/*.ts'],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        ecmaVersion: 2023,
        sourceType: 'module',
        project: './tsconfig.json',
      },
      globals: {
        NodeJS: 'readonly',
        console: 'readonly',
        process: 'readonly',
        setTimeout: 'readonly',
        clearTimeout: 'readonly',
        setInterval: 'readonly',
        clearInterval: 'readonly',
        Buffer: 'readonly',
        URL: 'readonly',
        TextEncoder: 'readonly',
        TextDecoder: 'readonly',
        fetch: 'readonly',
        PDFKit: 'readonly',
      },
    },
    plugins: { '@typescript-eslint': tsPlugin },
    rules: {
      ...tsPlugin.configs.recommended.rules,
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      '@typescript-eslint/consistent-type-imports': ['error', { prefer: 'type-imports' }],
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': 'error',
      '@typescript-eslint/explicit-module-boundary-types': 'off',
      'no-console': ['error', { allow: ['error'] }],
      eqeqeq: ['error', 'always'],
    },
  },
  prettier,
  {
    ignores: ['dist/**', 'node_modules/**', 'coverage/**', 'prisma/migrations/**'],
  },
];
