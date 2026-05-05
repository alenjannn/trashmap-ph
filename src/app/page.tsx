"use client";

import dynamic from "next/dynamic";

const AdminLoginGate = dynamic(() => import("@/components/layout/admin-login-gate").then((mod) => mod.AdminLoginGate), {
  ssr: false,
});

export default function Home() {
  return <AdminLoginGate />;
}
