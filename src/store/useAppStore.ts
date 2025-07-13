import { create } from 'zustand';
import { devtools } from 'zustand/middleware';
import { immer } from 'zustand/middleware/immer';

interface Product {
  id: string
  name: string
  price: number
  image: string
  category: string
}

interface User {
  id: string
  name: string
  email: string
}

interface CartItem {
  id: string
  name: string
  price: number
  image: string
  category: string
  quantity: number
}

interface AppState {
  // UI State
  isLoading: boolean
  theme: 'light' | 'dark'
  sidebarOpen: boolean

  // User State
  user: User | null
  isAuthenticated: boolean

  // Product State
  products: Product[]
  selectedProduct: Product | null
  cart: CartItem[]

  // Actions
  setLoading: (loading: boolean) => void
  toggleTheme: () => void
  toggleSidebar: () => void
  setSidebarOpen: (open: boolean) => void
  setUser: (user: User | null) => void
  setProducts: (products: Product[]) => void
  selectProduct: (product: Product | null) => void
  addToCart: (product: Product) => void
  removeFromCart: (productId: string) => void
  clearCart: () => void
}

export const useAppStore = create<AppState>()(
  devtools(
    immer((set) => ({
      // Initial State
      isLoading: false,
      theme: 'light',
      sidebarOpen: false,
      user: null,
      isAuthenticated: false,
      products: [],
      selectedProduct: null,
      cart: [],

      // Actions
      setLoading: (loading) => set((state) => ({ ...state, isLoading: loading })),

      toggleTheme: () => set((state) => ({ ...state, theme: state.theme === 'light' ? 'dark' : 'light' })),

      toggleSidebar: () => set((state) => ({ ...state, sidebarOpen: !state.sidebarOpen })),

      setSidebarOpen: (open) => set((state) => ({ ...state, sidebarOpen: open })),

      setUser: (user) => set((state) => ({ ...state, user, isAuthenticated: !!user })),

      setProducts: (products) => set((state) => ({ ...state, products })),

      selectProduct: (product) => set((state) => ({ ...state, selectedProduct: product })),

      addToCart: (product) => set((state) => {
        const existingItem = state.cart.find((item) => item.id === product.id);
        if (existingItem) {
          return {
            ...state,
            cart: state.cart.map((item) => (item.id === product.id
              ? { ...item, quantity: item.quantity + 1 }
              : item)),
          };
        }
        return { ...state, cart: [...state.cart, { ...product, quantity: 1 }] };
      }),

      removeFromCart: (productId) => set((state) => ({
        ...state,
        cart: state.cart.filter((item) => item.id !== productId),
      })),

      clearCart: () => set((state) => ({ ...state, cart: [] })),
    })),
    {
      name: 'jab-store',
    },
  ),
);

// Selectors
export const useCartCount = () => useAppStore((state) => state.cart.length);
export const useCartTotal = () => useAppStore((state) => state.cart.reduce((total, item) => total
  + item.price * item.quantity, 0));