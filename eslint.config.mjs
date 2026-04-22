import js from "@eslint/js";

export default [
  {
    files: ["themes/pager/assets/js/**/*.js"],
    languageOptions: {
      ecmaVersion: 2020,
      sourceType: "module",
      globals: {
        // Browser globals used by debug scripts. Kept explicit instead
        // of pulling in eslint's `browser` env so additions to this list
        // stay visible in review.
        window: "readonly",
        document: "readonly",
        navigator: "readonly",
        location: "readonly",
        innerWidth: "readonly",
        innerHeight: "readonly",
        devicePixelRatio: "readonly",
        performance: "readonly",
        getComputedStyle: "readonly",
        console: "readonly",
        localStorage: "readonly",
        fetch: "readonly",
        setTimeout: "readonly",
        setInterval: "readonly",
        clearInterval: "readonly",
        addEventListener: "readonly",
        HTMLElement: "readonly",
        PerformanceNavigationTiming: "readonly",
        DOMParser: "readonly",
      },
    },
    rules: {
      ...js.configs.recommended.rules,
      "no-unused-vars": ["warn", { argsIgnorePattern: "^_" }],
      "no-implicit-globals": "error",
      "no-var": "error",
      "prefer-const": "warn",
      eqeqeq: ["error", "smart"],
    },
  },
];
