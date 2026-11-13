-- Migration 0004: Video media support for posts
ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS video_url TEXT;
