
static __inline__ int blli_in_use(struct atm_blli blli)
{
  return blli.l2_proto || blli.l3_proto;
}
