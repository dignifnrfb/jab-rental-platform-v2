/* eslint-disable */
import { create } from 'zustand';
import { immer } from 'zustand/middleware/immer';
import type { Draft } from 'immer';

interface RentalProduct {
  id: string
  name: string
  category: string
  brand: string
  dailyPrice: number
  weeklyPrice: number
  monthlyPrice: number
  deposit: number
  image: string
  features: string[]
  availability: 'available' | 'limited' | 'unavailable'
  rating: number
  reviewCount: number
}

interface CartItem extends RentalProduct {
  quantity: number
  rentalPeriod: 'daily' | 'weekly' | 'monthly'
  startDate?: string
  endDate?: string
}

interface RentalOrder {
  id: string
  userId: string
  items: CartItem[]
  totalAmount: number
  status: 'pending' | 'confirmed' | 'active' | 'returned' | 'cancelled'
  startDate: string
  endDate: string
  createdAt: string
  updatedAt: string
}

interface User {
  id: string
  email: string
  name: string
  avatar?: string
  phone?: string
  address?: string
  isVerified: boolean
  role?: 'user' | 'admin'
}

interface RentalState {
  // User state
  user: User | null
  isAuthenticated: boolean

  // Cart state
  cart: CartItem[]
  cartOpen: boolean

  // Orders state
  orders: RentalOrder[]
  currentOrder: RentalOrder | null

  // UI state
  loading: boolean
  error: string | null
}

interface RentalActions {
  // User actions
  setUser: (user: User | null) => void
  login: (email: string, password: string) => Promise<boolean>
  logout: () => void
  register: (userData: Partial<User> & { password: string }) => Promise<boolean>

  // Cart actions
  addToCart: (product: RentalProduct, rentalPeriod?: 'daily' | 'weekly' | 'monthly') => void
  removeFromCart: (productId: string) => void
  updateCartItem: (productId: string, updates: Partial<CartItem>) => void
  clearCart: () => void
  setCartOpen: (open: boolean) => void

  // Order actions
  createOrder: (cartItems: CartItem[]) => Promise<string | null>
  getOrders: () => Promise<RentalOrder[]>
  updateOrderStatus: (orderId: string, status: RentalOrder['status']) => void

  // Utility actions
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
  calculateCartTotal: () => number
}

type RentalStore = RentalState & RentalActions;

export const useRentalStore = create<RentalStore>()(immer((set, get) => ({
  // Initial state
  user: null,
  isAuthenticated: false,
  cart: [],
  cartOpen: false,
  orders: [],
  currentOrder: null,
  loading: false,
  error: null,

  // User actions
  setUser: (user) => set((state: Draft<RentalStore>) => {
    state.user = user;
    state.isAuthenticated = !!user;
  }),

  login: async (email, password) => {
    set((state: Draft<RentalStore>) => {
      state.loading = true;
      state.error = null;
    });
    try {
      await new Promise((resolve) => {
        setTimeout(resolve, 1000);
      });
      // Simulate password check
      if (password === 'password') {
        const mockUser: User = {
          id: '1',
          email,
          name: email.split('@')[0] ?? '',
          isVerified: true,
        };
        set((state: Draft<RentalStore>) => {
          state.user = mockUser;
          state.isAuthenticated = true;
          state.loading = false;
        });
        return true;
      }
      throw new Error('Invalid credentials');
    } catch (error) {
      set((state: Draft<RentalStore>) => {
        state.error = '登录失败，请检查邮箱和密码';
        state.loading = false;
      });
      return false;
    }
  },

  logout: () => {
    set((state: Draft<RentalStore>) => {
      state.user = null;
      state.isAuthenticated = false;
      state.cart = [];
      state.orders = [];
    });
  },

  register: async (userData) => {
    set((state: Draft<RentalStore>) => {
      state.loading = true;
      state.error = null;
    });
    try {
      await new Promise((resolve) => {
        setTimeout(resolve, 1000);
      });
      const mockUser: User = {
        id: Date.now().toString(),
        email: userData.email!,
        name: userData.name!,
        phone: userData.phone ?? '',
        address: userData.address ?? '',
        isVerified: false,
      };
      set((state: Draft<RentalStore>) => {
        state.user = mockUser;
        state.isAuthenticated = true;
        state.loading = false;
      });
      return true;
    } catch (error) {
      set((state: Draft<RentalStore>) => {
        state.error = '注册失败，请稍后重试';
        state.loading = false;
      });
      return false;
    }
  },

  // Cart actions
  addToCart: (product, rentalPeriod = 'monthly') => set((state: Draft<RentalStore>) => {
    const existingItem = state.cart.find((item) => item.id === product.id && item.rentalPeriod === rentalPeriod);

    if (existingItem) {
      existingItem.quantity += 1;
    } else {
      state.cart.push({ ...product, quantity: 1, rentalPeriod });
    }
  }),

  removeFromCart: (productId) => {
    set((state: Draft<RentalStore>) => {
      const index = state.cart.findIndex((item) => item.id === productId);
      if (index !== -1) {
        state.cart.splice(index, 1);
      }
    });
  },

  updateCartItem: (productId, updates) => {
    set((state: Draft<RentalStore>) => {
      const item = state.cart.find((item) => item.id === productId);
      if (item) {
        Object.assign(item, updates);
      }
    });
  },

  clearCart: () => set((state: Draft<RentalStore>) => {
    state.cart = [];
  }),

  setCartOpen: (open) => set((state: Draft<RentalStore>) => {
    state.cartOpen = open;
  }),

  // Order actions
  createOrder: async (cartItems) => {
    const { user } = get();
    if (!user) {
      return null;
    }

    set((state: Draft<RentalStore>) => {
      state.loading = true;
      state.error = null;
    });

    try {
      await new Promise((resolve) => {
        setTimeout(resolve, 1000);
      });

      const orderId = `order_${Date.now()}`;
      const totalAmount = get().calculateCartTotal();

      const newOrder: RentalOrder = {
        id: orderId,
        userId: user.id,
        items: cartItems,
        totalAmount,
        status: 'pending',
        startDate: new Date().toISOString(),
        endDate: new Date(
          Date.now() + 30 * 24 * 60 * 60 * 1000,
        ).toISOString(), // 30 days later
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
      };

      set((state: Draft<RentalStore>) => {
        state.orders.push(newOrder);
        state.currentOrder = newOrder;
        state.cart = [];
        state.loading = false;
      });
      return orderId;
    } catch (error) {
      set((state: Draft<RentalStore>) => {
        state.error = '创建订单失败，请稍后重试';
        state.loading = false;
      });
      return null;
    }
  },

  getOrders: async () => {
    const { user } = get();
    if (!user) {
      return [];
    }

    set((state: Draft<RentalStore>) => {
      state.loading = true;
    });

    try {
      await new Promise((resolve) => {
        setTimeout(resolve, 500);
      });

      const orders = get().orders.filter((order) => order.userId === user.id);

      set((state: Draft<RentalStore>) => {
        state.loading = false;
      });
      return orders;
    } catch (error) {
      set((state: Draft<RentalStore>) => {
        state.error = '获取订单失败';
        state.loading = false;
      });
      return [];
    }
  },

  updateOrderStatus: (orderId, status) => set((state: Draft<RentalStore>) => {
    const order = state.orders.find((order) => order.id === orderId);
    if (order) {
      order.status = status;
      order.updatedAt = new Date().toISOString();
    }
  }),

  // Utility actions
  setLoading: (loading) => set((state: Draft<RentalStore>) => {
    state.loading = loading;
  }),

  setError: (error) => set((state: Draft<RentalStore>) => {
    state.error = error;
  }),

  calculateCartTotal: () => {
    const { cart } = get();
    return cart.reduce((total, item) => {
      const price = (() => {
        if (item.rentalPeriod === 'daily') {
          return item.dailyPrice;
        }
        if (item.rentalPeriod === 'weekly') {
          return item.weeklyPrice;
        }
        return item.monthlyPrice;
      })();
      return total + (price * item.quantity);
    }, 0);
  },
})));

// Export types for use in components
export type {
  RentalProduct, CartItem, RentalOrder, User,
};
