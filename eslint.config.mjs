import { dirname } from 'path'
import { fileURLToPath } from 'url'
import { FlatCompat } from '@eslint/eslintrc'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

const compat = new FlatCompat({
  baseDirectory: __dirname,
})

const config = [
  {
    // Generated / build output and nested worktrees.
    ignores: [
      '.next/**',
      'out/**',
      '.claude/**',
      'public/sw.js',
      'public/swe-worker-*.js',
      // Cargo 的构建产物。tauri-codegen 会把前端资源压缩后以 .js 落在这里，
      // 内容是二进制，eslint 解析会直接报错。
      'src-tauri/target/**',
    ],
  },
  ...compat.extends('next/core-web-vitals'),
  {
    rules: {
      '@typescript-eslint/no-unused-vars': 'off',
      'react/no-unescaped-entities': 'off',
      '@next/next/no-page-custom-font': 'off',
    },
  },
]

export default config
