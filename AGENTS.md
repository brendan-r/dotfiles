
New shell code should follow the style conventions in the repo:
- Spacious formatting, functionality split over lines, commenting what each line does
- Use #  - - -  style dividers to break up sections

Production target for Debian: Intel/AMD64 ThinkPads (X1 Carbon 6th gen, T480, X200T).
ARM64 VMs are a test environment, not the definition of supported functionality.
Preserve the intended desktop and hardware behaviour; detect CPU/device differences
where necessary rather than replacing or disabling functionality to satisfy a VM.
Report ARM-only coverage separately from Intel execution and physical hardware tests.
