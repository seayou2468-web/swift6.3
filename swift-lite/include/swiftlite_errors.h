#ifndef SWIFTLITE_ERRORS_H
#define SWIFTLITE_ERRORS_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum swiftlite_error_code : int32_t {
  SWL_OK = 0,
  SWL_ERR_INVALID_ARGUMENT = 1,
  SWL_ERR_SDK_NOT_FOUND = 2,
  SWL_ERR_RUNTIME_NOT_FOUND = 3,
  SWL_ERR_PARSE_FAILED = 4,
  SWL_ERR_AST_BRIDGE_FAILED = 5,
  SWL_ERR_SEMA_FAILED = 6,
  SWL_ERR_SIL_FAILED = 7,
  SWL_ERR_IRGEN_FAILED = 8,
  SWL_ERR_EMIT_FAILED = 9,
  SWL_ERR_UNSUPPORTED_SYNTAX = 10,
  SWL_ERR_INTERNAL = 127
} swiftlite_error_code;

const char *swiftlite_error_string(swiftlite_error_code code);

#ifdef __cplusplus
}
#endif

#endif // SWIFTLITE_ERRORS_H
