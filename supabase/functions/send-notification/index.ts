// Supabase Edge Function: send-notification
// Sends a notification to a user: inserts DB row + FCM push
// Deploy via: supabase functions deploy send-notification
// Requires secret: FCM_SERVER_KEY

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
    const fcmServerKey = Deno.env.get("FCM_SERVER_KEY");

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

    // Send FCM push if server key is configured
    if (fcmServerKey) {
      // Fetch all active device tokens for this user
      const { data: devices } = await supabase
        .from("user_devices")
        .select("fcm_token")
        .eq("user_id", recipient_user_id)
        .eq("is_active", true);

      if (devices && devices.length > 0) {
        const tokens = devices.map((d: { fcm_token: string }) => d.fcm_token);
        
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

        // Send to each token (FCM legacy API supports multicast)
        for (const token of tokens) {
          try {
            const fcmResponse = await fetch("https://fcm.googleapis.com/fcm/send", {
              method: "POST",
              headers: {
                "Authorization": `key=${fcmServerKey}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                to: token,
                notification: { title, body: message },
                data: fcmData,
                android: {
                  priority: "high",
                  notification: {
                    channel_id: "general_notifications",
                    sound: "default",
                  },
                },
              }),
            });

            const fcmResult = await fcmResponse.json();
            console.log(`[FCM] Token result:`, fcmResult);

            // Handle invalid/expired tokens
            if (fcmResult.failure > 0 && fcmResult.results) {
              for (const result of fcmResult.results) {
                if (result.error === "NotRegistered" || result.error === "InvalidRegistration") {
                  await supabase
                    .from("user_devices")
                    .update({ is_active: false })
                    .eq("fcm_token", token);
                  console.log(`[FCM] Deactivated invalid token: ${token.substring(0, 20)}...`);
                }
              }
            }
          } catch (fcmErr) {
            console.error("[FCM] Send error for token:", fcmErr);
          }
        }
      } else {
        console.log(`[Notification] No active devices for user ${recipient_user_id}`);
      }
    } else {
      console.log("[Notification] FCM_SERVER_KEY not set, skipping push.");
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
