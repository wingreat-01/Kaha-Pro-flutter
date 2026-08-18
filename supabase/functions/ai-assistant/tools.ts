// supabase/functions/ai-assistant/tools.ts
//
// Matches confirmed schema (verified live Aug 18 2026):
//   products(id, store_id, name, price, category_id NOT NULL, emoji,
//            image_path, stock_qty, low_stock_threshold, created_at,
//            updated_at, image_url, track_stock, unit NOT NULL default 'pc',
//            unit_label)
//   ingredients(id, store_id, name, unit, unit_label, stock_quantity,
//               low_stock_threshold, cost_per_unit, ...)
//   ingredient_stock_movements(id, store_id NOT NULL, ingredient_id NOT NULL,
//                              delta NOT NULL numeric, reason NOT NULL text,
//                              note, staff_id, staff_name,
//                              source NOT NULL, CHECK source in ('manual','sale'),
//                              created_at)
//   transactions(id, store_id, transaction_number, total,
//                cash_tendered, change_amount, cashier_name, created_at)
//   categories(id, name, ...) -- resolved by name via resolveCategoryId
//
// Still unverified (flagged inline): transaction_line_items beyond
// product_id/quantity. get_best_sellers is written to avoid needing
// to guess transaction_line_items' full shape -- it only relies on
// product_id + quantity existing on that table.

import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import type { ToolDef } from './types.ts';

export const TOOL_DEFS: ToolDef[] = [
  {
    name: 'add_product',
    description: 'Adds a new sellable product to the store catalog. Every product must belong to a category.',
    parameters: {
      type: 'object',
      properties: {
        name: { type: 'string' },
        price: { type: 'number', description: 'Selling price in PHP' },
        category_name: { type: 'string', description: 'Existing category name. Required -- every product must have a category.' },
        unit: { type: 'string', description: 'e.g. pc' },
        track_stock: { type: 'boolean', description: 'Whether stock is tracked for this product' },
        stock_qty: { type: 'number', description: 'Starting stock quantity, if track_stock is true' },
        low_stock_thresh: { type: 'number' },
      },
      required: ['name', 'price', 'category_name'],
    },
  },
  {
    name: 'update_product',
    description: 'Updates fields on an existing product. Only send fields being changed.',
    parameters: {
      type: 'object',
      properties: {
        product_id: { type: 'string' },
        name: { type: 'string' },
        price: { type: 'number' },
        category_name: { type: 'string' },
        stock_qty: { type: 'number' },
        low_stock_thresh: { type: 'number' },
      },
      required: ['product_id'],
    },
  },
  {
    name: 'add_ingredient',
    description: 'Adds a new ingredient/supply/material tracked in inventory.',
    parameters: {
      type: 'object',
      properties: {
        name: { type: 'string' },
        unit: { type: 'string', description: 'e.g. g, pc, ml' },
        cost_per_unit: { type: 'number' },
        initial_stock: { type: 'number' },
        low_stock: { type: 'number', description: 'Low-stock threshold' },
      },
      required: ['name', 'unit', 'cost_per_unit'],
    },
  },
  {
    name: 'update_ingredient',
    description: 'Updates fields on an existing ingredient. Only send fields being changed.',
    parameters: {
      type: 'object',
      properties: {
        ingredient_id: { type: 'string' },
        name: { type: 'string' },
        unit: { type: 'string' },
        cost_per_unit: { type: 'number' },
        low_stock: { type: 'number' },
      },
      required: ['ingredient_id'],
    },
  },
  {
    name: 'withdraw_inventory',
    description:
      'Deducts stock for a product or ingredient. Destructive -- first call without confirmed=true to get a summary, ' +
      'show it to the user, then call again with confirmed=true only after they explicitly agree.',
    parameters: {
      type: 'object',
      properties: {
        item_type: { type: 'string', enum: ['product', 'ingredient'] },
        item_id: { type: 'string' },
        quantity: { type: 'number' },
        reason: { type: 'string' },
        confirmed: { type: 'boolean', description: 'Set true only after the user has confirmed.' },
      },
      required: ['item_type', 'item_id', 'quantity'],
    },
  },
  {
    name: 'get_inventory',
    description: 'Returns current stock levels for products and/or ingredients.',
    parameters: {
      type: 'object',
      properties: {
        item_type: { type: 'string', enum: ['product', 'ingredient', 'all'] },
        low_stock_only: { type: 'boolean', description: 'Only items at or below their own low-stock threshold' },
      },
    },
  },
  {
    name: 'get_sales',
    description: 'Returns sales records between two dates (inclusive), ISO format YYYY-MM-DD.',
    parameters: {
      type: 'object',
      properties: {
        start_date: { type: 'string' },
        end_date: { type: 'string' },
      },
      required: ['start_date', 'end_date'],
    },
  },
  {
    name: 'get_best_sellers',
    description: 'Returns top-selling products by quantity between two dates.',
    parameters: {
      type: 'object',
      properties: {
        start_date: { type: 'string' },
        end_date: { type: 'string' },
        limit: { type: 'number' },
      },
      required: ['start_date', 'end_date'],
    },
  },
  {
    name: 'compare_sales',
    description: 'Compares total sales between two periods and returns the difference.',
    parameters: {
      type: 'object',
      properties: {
        period_a_start: { type: 'string' },
        period_a_end: { type: 'string' },
        period_b_start: { type: 'string' },
        period_b_end: { type: 'string' },
      },
      required: ['period_a_start', 'period_a_end', 'period_b_start', 'period_b_end'],
    },
  },
];

async function resolveCategoryId(supabase: SupabaseClient, categoryName?: string): Promise<string | null> {
  if (!categoryName) return null;
  const { data } = await supabase
    .from('categories')
    .select('id')
    .ilike('name', categoryName)
    .limit(1)
    .maybeSingle();
  return data?.id ?? null;
}

// Every tool below returns { error: message } to the model on a DB failure,
// but that message only reaches a human as the model's paraphrase of it in
// chat. Logging the raw error here too means the real Postgres error text
// (wrong column name, NOT NULL violation, RLS denial, etc.) is always
// visible via `supabase functions logs ai-assistant`, independent of
// whatever the model chooses to say about it.
function logToolError(tool: string, error: { message: string; code?: string; details?: string; hint?: string }): void {
  console.error(`[ai-assistant] ${tool} failed:`, error);
}

export async function executeTool(
  supabase: SupabaseClient,
  name: string,
  args: Record<string, unknown>,
): Promise<unknown> {
  switch (name) {
    case 'add_product': {
      const a = args as any;
      if (!a.category_name) {
        return { error: 'A category is required to add a product. Ask the user which category to use.' };
      }
      const category_id = await resolveCategoryId(supabase, a.category_name);
      if (!category_id) {
        return { error: `No category found named "${a.category_name}". Create the category first or ask which existing category to use.` };
      }
      const { data, error } = await supabase
        .from('products')
        .insert({
          name: a.name,
          price: a.price,
          category_id,
          unit: a.unit ?? 'pc',
          track_stock: a.track_stock ?? false,
          stock_qty: a.stock_qty ?? 0,
          low_stock_threshold: a.low_stock_thresh ?? 5,
        })
        .select()
        .single();
      if (error) {
        logToolError('add_product', error);
        return { error: error.message };
      }
      return { success: true, product: data };
    }

    case 'update_product': {
      const a = args as any;
      const fields: Record<string, unknown> = {};
      if (a.name !== undefined) fields.name = a.name;
      if (a.price !== undefined) fields.price = a.price;
      if (a.stock_qty !== undefined) fields.stock_qty = a.stock_qty;
      if (a.low_stock_thresh !== undefined) fields.low_stock_threshold = a.low_stock_thresh;
      const { category_name } = a;
      if (category_name) {
        const category_id = await resolveCategoryId(supabase, category_name);
        if (!category_id) return { error: `No category found named "${category_name}".` };
        fields.category_id = category_id;
      }
      const { data, error } = await supabase
        .from('products')
        .update(fields)
        .eq('id', a.product_id)
        .select()
        .single();
      if (error) {
        logToolError('update_product', error);
        return { error: error.message };
      }
      return { success: true, product: data };
    }

    case 'add_ingredient': {
      const a = args as any;
      const { data, error } = await supabase
        .from('ingredients')
        .insert({
          name: a.name,
          unit: a.unit,
          cost_per_unit: a.cost_per_unit,
          stock_quantity: a.initial_stock ?? 0,
          low_stock_threshold: a.low_stock ?? null,
        })
        .select()
        .single();
      if (error) {
        logToolError('add_ingredient', error);
        return { error: error.message };
      }
      return { success: true, ingredient: data };
    }

    case 'update_ingredient': {
      const a = args as { ingredient_id: string; low_stock?: number; [k: string]: unknown };
      const UPDATE_INGREDIENT_FIELDS = ['name', 'unit', 'cost_per_unit'] as const;
      const fields: Record<string, unknown> = {};
      for (const key of UPDATE_INGREDIENT_FIELDS) {
        if (a[key] !== undefined) fields[key] = a[key];
      }
      if (a.low_stock !== undefined) fields.low_stock_threshold = a.low_stock;
      const { data, error } = await supabase
        .from('ingredients')
        .update(fields)
        .eq('id', a.ingredient_id)
        .select()
        .single();
      if (error) {
        logToolError('update_ingredient', error);
        return { error: error.message };
      }
      return { success: true, ingredient: data };
    }

    case 'withdraw_inventory': {
      const { item_type, item_id, quantity, reason, confirmed } = args as {
        item_type: 'product' | 'ingredient';
        item_id: string;
        quantity: number;
        reason?: string;
        confirmed?: boolean;
      };
      if (!Number.isFinite(quantity) || quantity <= 0) {
        return { error: 'quantity must be a positive number.' };
      }

      const table = item_type === 'product' ? 'products' : 'ingredients';
      const stockCol = item_type === 'product' ? 'stock_qty' : 'stock_quantity';

      const { data: current, error: fetchErr } = await supabase
        .from(table)
        .select(`id, name, store_id, ${stockCol}`)
        .eq('id', item_id)
        .single();
      if (fetchErr) return { error: fetchErr.message };

      const currentStock = (current as any)[stockCol];

      if (!confirmed) {
        return {
          status: 'needs_confirmation',
          summary: `Withdraw ${quantity} of "${current.name}" (current stock: ${currentStock}). Ask the user to confirm, then call withdraw_inventory again with confirmed=true.`,
        };
      }
      if (currentStock < quantity) {
        return { error: `Insufficient stock: only ${currentStock} available.` };
      }

      const { data, error } = await supabase
        .from(table)
        .update({ [stockCol]: currentStock - quantity })
        .eq('id', item_id)
        .select()
        .single();
      if (error) {
        logToolError('withdraw_inventory', error);
        return { error: error.message };
      }

      if (item_type === 'ingredient') {
        // Verified schema (Aug 18 2026): id, store_id NOT NULL,
        // ingredient_id NOT NULL, delta NOT NULL, reason NOT NULL,
        // note NULL, staff_id NULL, staff_name NULL, source NOT NULL,
        // created_at. No 'quantity_change' column -- that was the bug
        // that made every insert here fail silently (PGRST204).
        const { error: moveErr } = await supabase.from('ingredient_stock_movements').insert({
          store_id: (current as any).store_id,
          ingredient_id: item_id,
          delta: -quantity,
          reason: reason ?? 'Not specified',
          source: 'manual', // CHECK constraint only allows 'manual' | 'sale' -- an AI-initiated withdrawal is a manual adjustment, not a POS sale
          staff_name: 'AI Assistant',
        });
        if (moveErr) {
          // Stock update above already succeeded -- don't fail the whole
          // withdrawal over a logging write, but don't swallow it silently
          // either.
          logToolError('withdraw_inventory (movement log)', moveErr);
        }
      }

      return { success: true, item: data };
    }

    case 'get_inventory': {
      const { item_type = 'all', low_stock_only } = args as {
        item_type?: 'product' | 'ingredient' | 'all';
        low_stock_only?: boolean;
      };
      const results: Record<string, unknown> = {};

      if (item_type === 'product' || item_type === 'all') {
        const { data, error } = await supabase
          .from('products')
          .select('id, name, stock_qty, low_stock_threshold, price, track_stock');
        if (error) {
          results.products = { error: error.message };
        } else {
          results.products = low_stock_only
            ? data.filter((p: any) => p.track_stock && p.stock_qty <= p.low_stock_threshold)
            : data;
        }
      }

      if (item_type === 'ingredient' || item_type === 'all') {
        const { data, error } = await supabase
          .from('ingredients')
          .select('id, name, stock_quantity, low_stock_threshold, unit, cost_per_unit');
        if (error) {
          results.ingredients = { error: error.message };
        } else {
          results.ingredients = low_stock_only
            ? data.filter((i: any) => i.low_stock_threshold != null && i.stock_quantity <= i.low_stock_threshold)
            : data;
        }
      }

      return results;
    }

    case 'get_sales': {
      const { start_date, end_date } = args as { start_date: string; end_date: string };
      const { data, error } = await supabase
        .from('transactions')
        .select('id, transaction_number, total, cash_tendered, change_amount, cashier_name, created_at')
        .gte('created_at', start_date)
        .lte('created_at', `${end_date}T23:59:59`);
      if (error) return { error: error.message };

      // Pre-aggregate by calendar day, including days with zero sales,
      // so the model never has to group/invent dates itself -- every
      // day in the requested range is already present here, with a
      // real (possibly 0) total. `total` below is computed here too,
      // not left for the model to sum, to avoid arithmetic drift.
      const dailyTotals = new Map<string, { total: number; count: number }>();
      for (const tx of data ?? []) {
        const day = (tx as any).created_at.slice(0, 10); // YYYY-MM-DD
        const entry = dailyTotals.get(day) ?? { total: 0, count: 0 };
        entry.total += (tx as any).total ?? 0;
        entry.count += 1;
        dailyTotals.set(day, entry);
      }

      const daily: { date: string; total: number; count: number }[] = [];
      const cursor = new Date(`${start_date}T00:00:00Z`);
      const last = new Date(`${end_date}T00:00:00Z`);
      while (cursor <= last) {
        const day = cursor.toISOString().slice(0, 10);
        const entry = dailyTotals.get(day) ?? { total: 0, count: 0 };
        daily.push({ date: day, total: entry.total, count: entry.count });
        cursor.setUTCDate(cursor.getUTCDate() + 1);
      }

      const total = daily.reduce((sum, d) => sum + d.total, 0);
      const transaction_count = daily.reduce((sum, d) => sum + d.count, 0);

      return {
        daily, // every date in range is listed once, zero-sales days included with total: 0
        total, // sum across the whole range -- use this exact figure, do not recompute
        transaction_count,
        transactions: data, // raw rows, kept for questions about individual sales
      };
    }

    case 'get_best_sellers': {
      const { start_date, end_date, limit = 5 } = args as {
        start_date: string;
        end_date: string;
        limit?: number;
      };

      const { data: txs, error: txErr } = await supabase
        .from('transactions')
        .select('id')
        .gte('created_at', start_date)
        .lte('created_at', `${end_date}T23:59:59`);
      if (txErr) return { error: txErr.message };
      if (!txs?.length) return { best_sellers: [] };

      // CHECK: assumes transaction_line_items has transaction_id, product_id, quantity.
      const { data: items, error: itemsErr } = await supabase
        .from('transaction_line_items')
        .select('product_id, quantity')
        .in('transaction_id', txs.map((t) => t.id));
      if (itemsErr) return { error: itemsErr.message };

      const totals = new Map<string, number>();
      for (const item of items ?? []) {
        const pid = (item as any).product_id;
        const qty = (item as any).quantity ?? 0;
        totals.set(pid, (totals.get(pid) ?? 0) + qty);
      }

      const topIds = [...totals.entries()].sort((a, b) => b[1] - a[1]).slice(0, limit);
      if (!topIds.length) return { best_sellers: [] };

      const { data: products, error: prodErr } = await supabase
        .from('products')
        .select('id, name')
        .in('id', topIds.map(([id]) => id));
      if (prodErr) return { error: prodErr.message };

      const nameById = new Map((products ?? []).map((p: any) => [p.id, p.name]));
      return {
        best_sellers: topIds.map(([id, qty]) => ({
          product_id: id,
          name: nameById.get(id) ?? 'Unknown',
          quantity_sold: qty,
        })),
      };
    }

    case 'compare_sales': {
      const { period_a_start, period_a_end, period_b_start, period_b_end } = args as {
        period_a_start: string;
        period_a_end: string;
        period_b_start: string;
        period_b_end: string;
      };
      const sum = async (start: string, end: string) => {
        const { data, error } = await supabase
          .from('transactions')
          .select('total')
          .gte('created_at', start)
          .lte('created_at', `${end}T23:59:59`);
        if (error) return { error: error.message };
        const total = (data ?? []).reduce((sum, r: any) => sum + (r.total ?? 0), 0);
        return { total, count: data?.length ?? 0 };
      };
      const a = await sum(period_a_start, period_a_end);
      const b = await sum(period_b_start, period_b_end);
      return { period_a: a, period_b: b };
    }

    default:
      return { error: `Unknown tool: ${name}` };
  }
}
