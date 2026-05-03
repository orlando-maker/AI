// Supabase Edge Function: notify-admin
// Deploy: supabase functions deploy notify-admin
// Trigger: Supabase Dashboard → Database → Webhooks
//   Table: reports   Event: INSERT   URL: <your edge function URL>
//
// Required secret: RESEND_API_KEY
//   Set in: Supabase Dashboard → Settings → Edge Function Secrets

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const ADMIN_EMAIL = "admin@orlandonell.com";
const FROM_EMAIL = "noreply@orlandonell.com"; // must be a verified Resend sender domain

serve(async (req: Request): Promise<Response> => {
  try {
    const payload = await req.json();
    const record = payload?.record;

    if (!record) {
      return new Response("no record", { status: 400 });
    }

    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (!resendKey) {
      return new Response("RESEND_API_KEY not set", { status: 500 });
    }

    const typeLabel = (record.type as string)
      .replace(/_/g, " ")
      .replace(/\b\w/g, (c: string) => c.toUpperCase());

    const subject = `New Report: ${typeLabel}`;
    const body = [
      `A new report has been submitted to Woodside Trail Report.`,
      ``,
      `Type:         ${typeLabel}`,
      `Description:  ${record.description ?? "(none)"}`,
      `Location:     ${record.location_lat?.toFixed(5)}, ${record.location_lng?.toFixed(5)}`,
      `Near:         ${record.nearest_street ?? "unknown"}`,
      `Cross Streets:${record.cross_streets ?? "none"}`,
      `Contact:      ${record.phone ?? record.email ?? "not provided"}`,
      `Submitted:    ${record.created_at}`,
      `Report ID:    ${record.id}`,
      ``,
      `Log in to the admin panel to review and update the status.`,
    ].join("\n");

    const emailPayload = {
      from: FROM_EMAIL,
      to: ADMIN_EMAIL,
      subject,
      text: body,
    };

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resendKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(emailPayload),
    });

    if (!response.ok) {
      const err = await response.text();
      console.error("Resend error:", err);
      return new Response(`Resend error: ${err}`, { status: 502 });
    }

    return new Response("notification sent", { status: 200 });
  } catch (err) {
    console.error("Edge function error:", err);
    return new Response(`error: ${err}`, { status: 500 });
  }
});
