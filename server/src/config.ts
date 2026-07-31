import dotenv from 'dotenv';

dotenv.config();

function required(name: string, fallback?: string): string {
  const value = process.env[name] ?? fallback;
  if (value === undefined) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export const config = {
  env: process.env.NODE_ENV ?? 'development',
  port: parseInt(process.env.PORT ?? '8080', 10),

  db: {
    host: required('DB_HOST', 'localhost'),
    port: parseInt(process.env.DB_PORT ?? '5432', 10),
    database: required('DB_NAME', 'printerupkeep'),
    user: required('DB_USER', 'printerupkeep'),
    password: required('DB_PASSWORD', 'printerupkeep'),
    // ≤25 concurrent users; 10 pooled connections is generous headroom.
    maxConnections: parseInt(process.env.DB_POOL_SIZE ?? '10', 10),
  },

  auth: {
    jwtSecret: required('JWT_SECRET', 'change-me-in-production'),
    tokenTtl: process.env.JWT_TTL ?? '12h',
  },

  uploads: {
    dir: process.env.UPLOAD_DIR ?? './uploads',
    maxFileSizeMb: parseInt(process.env.MAX_FILE_SIZE_MB ?? '20', 10),
  },

  // Where uploaded documents are stored. 'disk' keeps them on the local
  // UPLOAD_DIR volume (default); 'supabase' stores them in a Supabase Storage
  // bucket. When STORAGE_DRIVER is unset it auto-selects 'supabase' if a
  // SUPABASE_URL + service key are configured, else falls back to 'disk'.
  storage: {
    driver: (process.env.STORAGE_DRIVER as 'disk' | 'supabase' | undefined) ??
      (process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_KEY ? 'supabase' : 'disk'),
    supabase: {
      // Base URL of the Supabase (Kong) gateway, e.g. https://supabase.example.com
      url: (process.env.SUPABASE_URL ?? '').replace(/\/+$/, ''),
      // service_role key — required for the API to read/write Storage server-side.
      serviceKey: process.env.SUPABASE_SERVICE_KEY ?? '',
      bucket: process.env.SUPABASE_STORAGE_BUCKET ?? 'PrinterLogs',
    },
  },

  bootstrap: {
    adminUsername: process.env.ADMIN_USERNAME ?? 'admin',
    adminPassword: process.env.ADMIN_PASSWORD ?? 'ChangeMe123!',
    adminFullName: process.env.ADMIN_FULL_NAME ?? 'System Administrator',
  },
};
