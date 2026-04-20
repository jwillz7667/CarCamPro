# Security Policy

## Reporting a vulnerability

**Do not open a public GitHub issue for security-related reports.**

If you believe you have found a security vulnerability in CarCam Pro — including
any issue that could lead to unauthorized access, data exposure, privilege
escalation, denial of service, or bypass of the app's privacy guarantees —
please email:

> **jwillz7667@gmail.com**
> Subject: `[CARCAM-PRO SECURITY] <short description>`

Please include:

- A clear description of the vulnerability and its impact.
- Steps to reproduce (device model, iOS version, app build number).
- Any proof-of-concept code, screenshots, or videos.
- Your name and contact info if you'd like to be credited.

We commit to:

| Milestone | Target |
|:--|:--:|
| Acknowledge receipt | within **2 business days** |
| Initial triage + severity assessment | within **5 business days** |
| Fix + public disclosure (coordinated) | within **90 days** |

## Scope

In-scope:
- The CarCam Pro iOS application (all App Store, TestFlight, and internal
  distribution builds).
- Any first-party backend services the app communicates with (future phases).
- Issues in the build toolchain or CI configuration that expose production
  signing material.

Out-of-scope:
- Third-party Apple frameworks and operating system surfaces — please report
  these directly to Apple via the
  [Apple Security Bounty](https://security.apple.com/).
- Social engineering, physical attacks, or issues requiring a jailbroken
  device.
- Rate-limiting, denial-of-service, or brute-force attacks against endpoints.
- Vulnerabilities in test / sample / archived code (e.g. files under `docs/`).

## Disclosure philosophy

We prefer coordinated disclosure. We ask researchers to:

1. Give us a reasonable window to investigate and ship a fix before going
   public.
2. Not access, modify, or delete user data beyond what's necessary to
   demonstrate the issue.
3. Not perform testing against production user accounts or devices you don't
   own.

We commit to crediting researchers in release notes (unless you prefer to
stay anonymous) and do not pursue legal action against good-faith researchers
who abide by this policy.
