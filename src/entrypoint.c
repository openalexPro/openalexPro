// We need to forward routine registration from C to Rust
// to avoid the linker removing the static library.

void R_init_openalex_pro_extendr(void *dll);
void register_extendr_panic_hook(void);

/* R looks for R_init_<exact-package-name> — must match the DESCRIPTION Package field. */
void R_init_openalexPro(void *dll) {
    register_extendr_panic_hook();
    R_init_openalex_pro_extendr(dll);
}
