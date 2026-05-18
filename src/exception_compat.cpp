#include "skate3_init.h"

#include <cstdint>

extern "C" REX_FUNC(__imp__sub_82F44E40);

extern "C" REX_FUNC(sub_82F44E40) {
  constexpr uint32_t kExceptionTrampoline = 0x83092CC0u;
  const uint32_t trampoline = REX_LOAD_U32(kExceptionTrampoline);
  if (trampoline == 0u) {
    ctx.r3.u64 = 0;
    return;
  }

  __imp__sub_82F44E40(ctx, base);
}
