import fs from 'fs';
import path from 'path';
import { config } from '../../config';

/**
 * Object storage abstraction for uploaded documents.
 *
 * Two drivers, selected by STORAGE_DRIVER (see config.storage):
 *   * 'disk'     — files live on the local UPLOAD_DIR volume (default).
 *   * 'supabase' — files live in a Supabase Storage bucket, accessed through
 *                  the Storage REST API with the service_role key.
 *
 * Both use the same opaque `key` — a bucket-relative path like
 * `<ticketId>/<random>-<name>` — which is what we persist in
 * ticket_files.storage_path. Callers never touch the filesystem or HTTP
 * directly, so switching drivers is a config change, not a code change.
 */
export interface StoredObject {
  buffer: Buffer;
  contentType?: string;
}

export interface FileStorage {
  readonly driver: 'disk' | 'supabase';
  put(key: string, data: Buffer, contentType: string): Promise<void>;
  get(key: string): Promise<StoredObject>;
  delete(key: string): Promise<void>;
}

class DiskStorage implements FileStorage {
  readonly driver = 'disk' as const;
  constructor(private readonly root: string) {}

  // Resolve a key to an absolute path, refusing anything that escapes root.
  private resolve(key: string): string {
    const full = path.resolve(this.root, key);
    if (!full.startsWith(path.resolve(this.root))) {
      throw new Error(`Invalid storage key: ${key}`);
    }
    return full;
  }

  async put(key: string, data: Buffer): Promise<void> {
    const full = this.resolve(key);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, data);
  }

  async get(key: string): Promise<StoredObject> {
    const full = this.resolve(key);
    if (!fs.existsSync(full)) throw new StorageNotFound(key);
    return { buffer: fs.readFileSync(full) };
  }

  async delete(key: string): Promise<void> {
    const full = this.resolve(key);
    if (fs.existsSync(full)) fs.unlinkSync(full);
  }
}

class SupabaseStorage implements FileStorage {
  readonly driver = 'supabase' as const;

  constructor(
    private readonly baseUrl: string,
    private readonly serviceKey: string,
    private readonly bucket: string,
  ) {
    if (!baseUrl || !serviceKey) {
      throw new Error(
        'STORAGE_DRIVER=supabase requires SUPABASE_URL and SUPABASE_SERVICE_KEY to be set',
      );
    }
  }

  // Storage REST object endpoint. Each path segment is encoded so keys with
  // spaces/parentheses in the (already sanitised) file name are still valid.
  private objectUrl(key: string): string {
    const encoded = key.split('/').map(encodeURIComponent).join('/');
    return `${this.baseUrl}/storage/v1/object/${encodeURIComponent(this.bucket)}/${encoded}`;
  }

  private get headers(): Record<string, string> {
    return {
      Authorization: `Bearer ${this.serviceKey}`,
      apikey: this.serviceKey,
    };
  }

  async put(key: string, data: Buffer, contentType: string): Promise<void> {
    const res = await fetch(this.objectUrl(key), {
      method: 'POST',
      headers: {
        ...this.headers,
        'Content-Type': contentType || 'application/octet-stream',
        'x-upsert': 'true',
      },
      body: data,
    });
    if (!res.ok) {
      throw new Error(`Supabase Storage upload failed (${res.status}): ${await safeBody(res)}`);
    }
  }

  async get(key: string): Promise<StoredObject> {
    const res = await fetch(this.objectUrl(key), { headers: this.headers });
    if (res.status === 404) throw new StorageNotFound(key);
    if (!res.ok) {
      throw new Error(`Supabase Storage download failed (${res.status}): ${await safeBody(res)}`);
    }
    const buffer = Buffer.from(await res.arrayBuffer());
    return { buffer, contentType: res.headers.get('content-type') ?? undefined };
  }

  async delete(key: string): Promise<void> {
    const res = await fetch(this.objectUrl(key), { method: 'DELETE', headers: this.headers });
    // Treat a missing object as already-deleted so retries stay idempotent.
    if (!res.ok && res.status !== 404) {
      throw new Error(`Supabase Storage delete failed (${res.status}): ${await safeBody(res)}`);
    }
  }
}

/** Thrown when an object key does not exist; routes map this to a 404. */
export class StorageNotFound extends Error {
  constructor(key: string) {
    super(`Object not found: ${key}`);
    this.name = 'StorageNotFound';
  }
}

async function safeBody(res: Response): Promise<string> {
  try {
    return (await res.text()).slice(0, 300);
  } catch {
    return '<no body>';
  }
}

function build(): FileStorage {
  if (config.storage.driver === 'supabase') {
    const s = config.storage.supabase;
    return new SupabaseStorage(s.url, s.serviceKey, s.bucket);
  }
  return new DiskStorage(config.uploads.dir);
}

export const fileStorage: FileStorage = build();
