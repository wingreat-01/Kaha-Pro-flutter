/// Supabase project connection details.
///
/// The anon/publishable key here is safe to ship in the client — it's
/// the public key meant for exactly this, and access control is
/// enforced by Row Level Security policies on the Supabase side, not by
/// keeping this key secret. Never put the `service_role` key anywhere
/// in the app — that one *is* a secret and belongs only on a trusted
/// server (e.g. inside an Edge Function), never on-device.
///
/// If this repo is ever made public and you'd rather not have infra
/// config sitting in source control at all, these can be swapped for
/// --dart-define values later — small change from here, not needed now.
class SupabaseConfig {
  static const String url = 'https://uykrnoxlzlvjtazicjim.supabase.co';
  static const String publishableKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InV5a3Jub3hsemx2anRhemljamltIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU1NjE3MDcsImV4cCI6MjEwMTEzNzcwN30.dLqbFc9NOn1fdyTlnlduz86Jl4fxw8KqSaY7Ra8MzbE';
}
