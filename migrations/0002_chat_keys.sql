-- 0002_chat_keys.sql
-- Keys for end-to-end encrypted chats. The API also creates this table on first use.
-- Private keys are stored encrypted with each user's chat password (PBKDF2 + AES-GCM);
-- the server never sees them or the message plaintext.

CREATE TABLE IF NOT EXISTS public.chat_keys (
    user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    public_key TEXT NOT NULL,
    encrypted_private_key TEXT NOT NULL,
    key_nonce TEXT NOT NULL,
    kdf_salt TEXT NOT NULL,
    kdf_iterations INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
