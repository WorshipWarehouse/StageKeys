#ifndef STAGEKEYS_CREAMCOAT_H
#define STAGEKEYS_CREAMCOAT_H
// Control thread creates/destroys. Audio thread owns configure/reset/frame.
typedef struct SKCreamCoat SKCreamCoat;
SKCreamCoat *sk_cream_create(double rate);
void sk_cream_destroy(SKCreamCoat *s);
void sk_cream_reset(SKCreamCoat *s);
void sk_cream_configure(SKCreamCoat *s,float size,float reflectivity,float quality,float predelayAmount);
void sk_cream_frame(SKCreamCoat *s,float *left,float *right);
#endif
