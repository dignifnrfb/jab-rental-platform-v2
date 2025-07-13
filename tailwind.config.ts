import type { Config } from 'tailwindcss';

const config: Config = {
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        // Modern Gray Scale System
        gray: {
          50: '#f5f5f7',
          100: '#e1e1e6',
          200: '#d2d2d7',
          300: '#b7b7bd',
          400: '#98989d',
          500: '#6e6e73',
          600: '#515154',
          700: '#424245',
          800: '#2c2c2e',
          900: '#1d1d1f',
        },
        // Modern Brand Blue
        blue: {
          500: '#0071e3',
          600: '#0077ed',
        },
        // Legacy colors for compatibility
        border: 'hsl(var(--border))',
        input: 'hsl(var(--input))',
        ring: 'hsl(var(--ring))',
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
        primary: {
          DEFAULT: 'hsl(var(--primary))',
          foreground: 'hsl(var(--primary-foreground))',
        },
        secondary: {
          DEFAULT: 'hsl(var(--secondary))',
          foreground: 'hsl(var(--secondary-foreground))',
        },
        destructive: {
          DEFAULT: 'hsl(var(--destructive))',
          foreground: 'hsl(var(--destructive-foreground))',
        },
        muted: {
          DEFAULT: 'hsl(var(--muted))',
          foreground: 'hsl(var(--muted-foreground))',
        },
        accent: {
          DEFAULT: 'hsl(var(--accent))',
          foreground: 'hsl(var(--accent-foreground))',
        },
        popover: {
          DEFAULT: 'hsl(var(--popover))',
          foreground: 'hsl(var(--popover-foreground))',
        },
        card: {
          DEFAULT: 'hsl(var(--card))',
          foreground: 'hsl(var(--card-foreground))',
        },
      },
      borderRadius: {
        lg: 'var(--radius)',
        md: 'calc(var(--radius) - 2px)',
        sm: 'calc(var(--radius) - 4px)',
      },
      fontFamily: {
        inter: ['Inter', 'system-ui', 'sans-serif'],
        sans: ['Inter', 'system-ui', 'sans-serif'],
      },
      fontSize: {
        'display-large': ['80px', { lineHeight: '84px', letterSpacing: '-0.5px', fontWeight: '300' }],
        'display-medium': ['64px', { lineHeight: '68px', letterSpacing: '-0.5px', fontWeight: '300' }],
        'display-small': ['48px', { lineHeight: '52px', letterSpacing: '-0.5px', fontWeight: '300' }],
        'headline-large': ['40px', { lineHeight: '44px', letterSpacing: '-0.5px', fontWeight: '300' }],
        'headline-medium': ['32px', { lineHeight: '36px', letterSpacing: '-0.5px', fontWeight: '300' }],
        'headline-small': ['24px', { lineHeight: '28px', letterSpacing: '-0.5px', fontWeight: '300' }],
      },
      spacing: {
        xxs: '4px',
        xs: '8px',
        sm: '12px',
        md: '16px',
        lg: '24px',
        xl: '32px',
        xxl: '48px',
        xxxl: '64px',
      },
      animation: {
        'fade-in': 'fadeIn 0.5s ease-in-out',
        'slide-up': 'slideUp 0.5s ease-out',
        'slide-down': 'slideDown 0.5s ease-out',
        'scale-in': 'scaleIn 0.3s ease-out',
        'bounce-subtle': 'bounceSubtle 2s infinite',
      },
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        slideUp: {
          '0%': { transform: 'translateY(20px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        slideDown: {
          '0%': { transform: 'translateY(-20px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        scaleIn: {
          '0%': { transform: 'scale(0.9)', opacity: '0' },
          '100%': { transform: 'scale(1)', opacity: '1' },
        },
        bounceSubtle: {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-5px)' },
        },
      },
      backdropBlur: {
        xs: '2px',
        standard: '14px',
      },
      boxShadow: {
        'modern-card': '0 12px 48px rgba(0, 0, 0, 0.08)',
        'modern-modal': '0 25px 50px -12px rgba(0, 0, 0, 0.25)',
        'modern-button': '0 4px 14px 0 rgba(0, 113, 227, 0.39)',
      },
    },
  },
  plugins: [],
};

export default config;
