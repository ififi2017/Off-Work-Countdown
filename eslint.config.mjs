import nextPlugin from '@next/eslint-plugin-next'
import reactPlugin from 'eslint-plugin-react'
import hooksPlugin from 'eslint-plugin-react-hooks'
import typescriptPlugin from '@typescript-eslint/eslint-plugin'

export default [
  {
    plugins: {
      '@next': nextPlugin,
      'react': reactPlugin,
      'react-hooks': hooksPlugin,
      '@typescript-eslint': typescriptPlugin
    },
    rules: {
      '@typescript-eslint/no-unused-vars': 'off',
      'react/no-unescaped-entities': 'off',
      '@next/next/no-page-custom-font': 'off',
    }
  }
] 