PTBS:

Add new canvas

sui client ptb \
--assign admin_cap @[ADDRESS] \
--assign base_paint_fee 100 \
--assign pixel_price_multiplier_reset_ms 1000 \
--assign paint_coin_fee 100000000 \
--move-call @[ADDRESS]::canvas_admin::new_rules base_paint_fee pixel_price_multiplier_reset_ms @0x0 paint_coin_fee \
--assign rules \
--assign meta_canvas @@[ADDRESS] \
--move-call @[ADDRESS]::meta_canvas::add_new_canvas \
meta_canvas admin_cap rules
