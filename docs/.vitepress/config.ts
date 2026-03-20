import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'Swarm',
  description: 'Multi-agent orchestration for Swift — built for production, not demos.',
  base: '/Swarm/',

  head: [
    // Satoshi from Fontshare
    ['link', { rel: 'stylesheet', href: 'https://api.fontshare.com/v2/css?f[]=satoshi@300,400,500,600&display=swap' }],
    // Syne + JetBrains Mono from Google Fonts
    ['link', { rel: 'preconnect', href: 'https://fonts.googleapis.com' }],
    ['link', { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' }],
    ['link', { rel: 'stylesheet', href: 'https://fonts.googleapis.com/css2?family=Syne:wght@400;500;600;700;800&family=JetBrains+Mono:ital,wght@0,400;0,500;1,400&display=swap' }],
    // Favicon
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/logo.svg' }],
  ],

  ignoreDeadLinks: true,
  appearance: 'dark',
  lastUpdated: true,
  cleanUrls: true,

  // Exclude internal planning docs that contain raw angle brackets
  srcExclude: [
    '**/BEST_PRACTICES.md',
    '**/DSL_IMPLEMENTATION_PROGRESS.md',
    '**/HIVE_V1_*.md',
    '**/SMART_GRAPH_COMPILATION_PLAN.md',
    '**/VOICE_AGENT_IMPLEMENTATION_PLAN.md',
    '**/migration-plan_*.md',
    '**/subagent-context-findings.md',
    '**/MultiProvider.md',
    '**/plans/**',
    '**/validation/**',
    '**/work-packages/**',
  ],

  themeConfig: {
    logo: '/logo.svg',

    nav: [
      { text: 'Guide', link: '/guide/getting-started' },
      { text: 'API Reference', link: '/reference/overview' },
      { text: 'GitHub', link: 'https://github.com/christopherkarani/Swarm' },
    ],

    sidebar: {
      '/guide/': [
        {
          text: 'Introduction',
          items: [
            { text: 'Getting Started', link: '/guide/getting-started' },
            { text: 'Agent Workspace', link: '/guide/agent-workspace' },
            { text: 'Why Swarm', link: '/guide/why-swarm' },
          ]
        },
        {
          text: 'API Reference',
          items: [
            { text: 'Overview', link: '/reference/overview' },
            { text: 'Complete Reference', link: '/swarm-complete-reference' },
          ]
        },
      ],
      '/reference/': [
        {
          text: 'API Reference',
          items: [
            { text: 'Overview', link: '/reference/overview' },
            { text: 'Complete Reference', link: '/swarm-complete-reference' },
          ]
        },
      ],
    },

    socialLinks: [
      { icon: 'github', link: 'https://github.com/christopherkarani/Swarm' },
      { icon: 'x', link: 'https://x.com/ckarani7' },
    ],

    search: {
      provider: 'local',
    },

    editLink: {
      pattern: 'https://github.com/christopherkarani/Swarm/edit/main/docs/:path',
      text: 'Edit this page on GitHub',
    },

    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Copyright © 2025-present Christopher Karani',
    },
  },
})
