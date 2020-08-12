/**
 * Package with constants used by Muntjac
 */
package muntjac_pkg;

//////////////////////////////////
// Control and status registers //
//////////////////////////////////

// Privileged mode
typedef enum logic[1:0] {
  PRIV_LVL_M = 2'b11,
  PRIV_LVL_H = 2'b10,
  PRIV_LVL_S = 2'b01,
  PRIV_LVL_U = 2'b00
} priv_lvl_e;

endpackage
