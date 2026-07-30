import nextCoreWebVitals from "eslint-config-next/core-web-vitals"
import nextTypeScript from "eslint-config-next/typescript"

const eslintConfig = [
  {
    ignores: [
      ".next/**",
      "out/**",
      "build/**",
      "node_modules/**",
      "next-env.d.ts",
      "design-system/**",
    ],
  },
  ...nextCoreWebVitals,
  ...nextTypeScript,
  {
    rules: {
      // The Supabase RPC payloads and the Ledmi insight blobs are dynamically
      // shaped; tighten this to "error" once those responses are typed.
      "@typescript-eslint/no-explicit-any": "warn",
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],

      // React Compiler rules, new in the Next 16 config. They fire on two
      // patterns this codebase uses deliberately:
      //   1. fetch-on-mount in a client component (ai-chat, business-snapshot,
      //      push-notifications, navigation-progress) — clearing these means
      //      adopting a server-cache library, which is a deliberate
      //      architectural change rather than a lint fix.
      //   2. vendored shadcn/ui primitives (ui/carousel, ui/sidebar,
      //      hooks/use-mobile), which should be re-synced from upstream rather
      //      than hand-patched.
      // Kept as warnings so they stay visible without blocking the gate.
      "react-hooks/set-state-in-effect": "warn",
      "react-hooks/purity": "warn",
      "react-hooks/immutability": "warn",
    },
  },
]

export default eslintConfig
