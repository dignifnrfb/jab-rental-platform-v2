import type { Draft } from 'immer';
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
      setLoading: (loading) => set((state: Draft<AppState>) => {
        state.isLoading = loading;
      }),

      toggleTheme: () => set((state: Draft<AppState>) => {
        state.theme = state.theme === 'light' ? 'dark' : 'light';
      }),

      toggleSidebar: () => set((state: Draft<AppState>) => {
        state.sidebarOpen = !state.sidebarOpen;
      }),

      setSidebarOpen: (open) => set((state: Draft<AppState>) => {
        state.sidebarOpen = open;
      }),

      setUser: (user) => set((state: Draft<AppState>) => {
        state.user = user;
        state.isAuthenticated = !!user;
      }),

      setProducts: (products) => set((state: Draft<AppState>) => {
        state.products = products;
      }),

      selectProduct: (product) => set((state: Draft<AppState>) => {
        state.selectedProduct = product;
      }),

      addToCart: (product) => set((state: Draft<AppState>) => {
        const existingItem = state.cart.find((item) => item.id === product.id);
        if (existingItem) {
          existingItem.quantity += 1;
        } else {
          state.cart.push({ ...product, quantity: 1 });
        }
      }),

      removeFromCart: (productId) => set((state: Draft<AppState>) => {
        const index = state.cart.findIndex((item) => item.id === productId);
        if (index !== -1) {
          state.cart.splice(index, 1);
        }
      }),

      clearCart: () => set((state: Draft<AppState>) => {
        state.cart = [];
      }),
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
