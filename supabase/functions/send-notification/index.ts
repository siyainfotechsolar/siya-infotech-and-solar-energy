// Supabase Edge Function: send-notification
// Sends a notification to a user: inserts DB row + FCM push (HTTP v1 API)
// Deploy via: supabase functions deploy send-notification
// Requires secret: FIREBASE_SERVICE_ACCOUNT (JSON string of the service account key)

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { encode as base64url } from "https://deno.land/std@0.177.0/encoding/base64url.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface NotificationPayload {
  recipient_user_id: string;
  notification_type: string;
  title: string;
  message: string;
  related_record_id?: string;
  task_id?: string;
  dispatch_id?: string;
  metadata?: Record<string, unknown>;
  event_id?: string;
}

// ─── FCM HTTP v1 Auth ─────────────────────────────────────────────────────
// Creates a short-lived OAuth2 access token from a service account JSON key
async function getAccessToken(serviceAccount: {
  client_email: string;
  private_key: string;
  token_uri: string;
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: serviceAccount.token_uri,
    iat: now,
    exp: now + 3600,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  };

  // Encode header and payload
  const enc = new TextEncoder();
  const headerB64 = base64url(enc.encode(JSON.stringify(header)));
  const payloadB64 = base64url(enc.encode(JSON.stringify(payload)));
  const unsignedToken = `${headerB64}.${payloadB64}`;

  // Import RSA private key and sign
  const pemContents = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\n/g, "");

  const binaryKey = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    enc.encode(unsignedToken)
  );
  const signatureB64 = base64url(new Uint8Array(signature));
  const jwt = `${unsignedToken}.${signatureB64}`;

  // Exchange JWT for access token
  const tokenResponse = await fetch(serviceAccount.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  const tokenData = await tokenResponse.json();
  if (!tokenData.access_token) {
    throw new Error(`Failed to get access token: ${JSON.stringify(tokenData)}`);
  }
  return tokenData.access_token;
}

// ─── Send FCM v1 Push ──────────────────────────────────────────────────────
async function sendFcmV1Push(
  projectId: string,
  accessToken: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>
): Promise<{ success: boolean; error?: string }> {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data,
        android: {
          priority: "high",
          notification: {
            channel_id: "general_notifications",
            sound: "default",
          },
        },
      },
    }),
  });

  if (response.ok) {
    return { success: true };
  }

  const errorBody = await response.text();
  console.error(`[FCM v1] Error ${response.status}: ${errorBody}`);

  // Check for unregistered token
  if (errorBody.includes("UNREGISTERED") || errorBody.includes("NOT_FOUND")) {
    return { success: false, error: "UNREGISTERED" };
  }

  return { success: false, error: errorBody };
}

// ─── Main Handler ──────────────────────────────────────────────────────────
serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Only allow POST
    if (req.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Use service_role client to bypass RLS for notification inserts
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const firebaseServiceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const payload: NotificationPayload = await req.json();

    const {
      recipient_user_id,
      notification_type,
      title,
      message,
      related_record_id,
      task_id,
      dispatch_id,
      metadata,
      event_id,
    } = payload;

    // Validate required fields
    if (!recipient_user_id || !notification_type || !title || !message) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: recipient_user_id, notification_type, title, message" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Deduplication: check if event_id already processed
    if (event_id) {
      const { data: existing } = await supabase
        .from("notifications")
        .select("id")
        .eq("recipient_user_id", recipient_user_id)
        .eq("event_id", event_id)
        .maybeSingle();

      if (existing) {
        console.log(`[Notification] Duplicate event_id detected: ${event_id}, skipping.`);
        return new Response(
          JSON.stringify({ success: true, duplicate: true, id: existing.id }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // Insert notification row
    const { data: notification, error: insertError } = await supabase
      .from("notifications")
      .insert({
        recipient_user_id,
        user_id: recipient_user_id, // keep legacy column in sync
        notification_type,
        title,
        message,
        related_record_id: related_record_id ?? null,
        task_id: task_id ?? null,
        dispatch_id: dispatch_id ?? null,
        metadata: metadata ?? null,
        event_id: event_id ?? null,
        is_read: false,
        created_at: new Date().toISOString(),
      })
      .select("id")
      .single();

    if (insertError) {
      console.error("[Notification] Insert error:", insertError);
      return new Response(
        JSON.stringify({ error: insertError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`[Notification] Created: ${notification.id} type=${notification_type} for user=${recipient_user_id}`);

    // Send FCM push if service account is configured
    if (firebaseServiceAccountJson) {
      try {
        const serviceAccount = JSON.parse(firebaseServiceAccountJson);
        const projectId = serviceAccount.project_id;
        const accessToken = await getAccessToken(serviceAccount);

        // Fetch all active device tokens for this user
        const { data: devices } = await supabase
          .from("user_devices")
          .select("fcm_token")
          .eq("user_id", recipient_user_id)
          .eq("is_active", true);

        if (devices && devices.length > 0) {
          // Build FCM data payload
          const fcmData: Record<string, string> = {
            notification_type,
            title,
            message,
          };
          if (related_record_id) fcmData.related_record_id = related_record_id;
          if (task_id) fcmData.task_id = task_id;
          if (dispatch_id) fcmData.dispatch_id = dispatch_id;
          if (notification?.id) fcmData.notification_id = notification.id;

          // Send to each device token
          for (const device of devices) {
            const result = await sendFcmV1Push(
              projectId,
              accessToken,
              device.fcm_token,
              title,
              message,
              fcmData
            );

            if (!result.success && result.error === "UNREGISTERED") {
              // Deactivate invalid/expired token
              await supabase
                .from("user_devices")
                .update({ is_active: false })
                .eq("fcm_token", device.fcm_token);
              console.log(`[FCM v1] Deactivated unregistered token: ${device.fcm_token.substring(0, 20)}...`);
            }
          }
        } else {
          console.log(`[Notification] No active devices for user ${recipient_user_id}`);
        }
      } catch (fcmErr) {
        // FCM failure must not break notification insert
        console.error("[FCM v1] Push delivery error (non-fatal):", fcmErr);
      }
    } else {
      console.log("[Notification] FIREBASE_SERVICE_ACCOUNT not set, skipping push.");
    }

    return new Response(
      JSON.stringify({ success: true, id: notification.id }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("[Notification] Unhandled error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
