library(ggfortify)
library(forecast)
library(tseries)
library(Metrics)
library(lmtest)
library(fpp2)
library(lmtest)
library(ggplot2)
library(readxl)
library(tidyr)
library(openxlsx)
library(scales)
library(qcc)         

# Impor data dan deret waktu

mentah <- read_excel("idr-usd.xlsx")
idr <- ts(mentah$IDR, start=c(2026, 1), frequency = 148) ; idr

plot(idr, 
     main="Plot Nilai IDR per USD", 
     ylab="Nilai", 
     xlab="Tahun", 
     col="blue", 
     lwd=2)

# Pemeriksaan stasioneritas
lambda <- BoxCox.lambda(idr); lambda

adf.test(idr)

idrd1 <- diff(idr,1)
adf.test(idrd1)

plot(idrd1, 
     main="Selisih pertama nilai tukar IDR per USD", 
     ylab="Nilai", 
     xlab="Tahun", 
     col="blue", 
     lwd=2)

acf(idrd1)
pacf(idrd1)

# Pemilihan model ARIMA
model1  <- Arima(idr, c(0,1,0))
model2  <- Arima(idr, c(0,1,1))
model3  <- Arima(idr, c(0,1,2))
model4  <- Arima(idr, c(1,1,0))
model5  <- Arima(idr, c(1,1,1))
model6  <- Arima(idr, c(2,1,0))
model7  <- Arima(idr, c(2,1,1))
model8  <- Arima(idr, c(2,1,2))
model9  <- Arima(idr, c(1,1,2))
model10 <- auto.arima(idr, d=1)

summary(model1);  summary(model2);  summary(model3)
summary(model4);  summary(model5);  summary(model6)
summary(model7);  summary(model8);  summary(model9)
summary(model10)

aic_table <- data.frame(
  Model = c("ARIMA(0,1,0)", "ARIMA(0,1,1)", "ARIMA(0,1,2)", 
            "ARIMA(1,1,0)", "ARIMA(1,1,1)", "ARIMA(2,1,0)", 
            "ARIMA(2,1,1)", "ARIMA(2,1,2)", "ARIMA(1,1,2)", 
            "Auto ARIMA"),
  AIC = c(AIC(model1), AIC(model2), AIC(model3), 
          AIC(model4), AIC(model5), AIC(model6), 
          AIC(model7), AIC(model8), AIC(model9), 
          AIC(model10)),
  BIC = c(BIC(model1), BIC(model2), BIC(model3), 
          BIC(model4), BIC(model5), BIC(model6), 
          BIC(model7), BIC(model8), BIC(model9), 
          BIC(model10))
)

aic_table <- aic_table[order(aic_table$AIC), ]
print(aic_table)
best_model <- model10

coeftest(best_model)

fc_terbaik <- forecast(best_model, h = 30)
model_label <- fc_terbaik$method

# Diagnostik residual
residual_terbaik <- residuals(best_model)
ks.test(residual_terbaik, "pnorm", mean(residual_terbaik), sd(residual_terbaik))

qqnorm(residual_terbaik, main = paste("QQ-plot residual", model_label))
qqline(residual_terbaik, col = "red")

lags <- c(6, 12, 24)
lapply(lags, function(l) Box.test(residual_terbaik, lag = l, type = "Ljung-Box"))
lapply(lags, function(l) Box.test(residual_terbaik^2, lag = l, type = "Ljung-Box"))

# Galat dalam sampel
MAPE <- mean(abs((idr - fitted(best_model)) / idr)) * 100 
MAPE

# Peta kendali residual
res_vec <- as.numeric(residual_terbaik)
cl_res  <- mean(res_vec)
sd_res  <- sd(res_vec)
ucl_res <- cl_res + 2 * sd_res
lcl_res <- cl_res - 2 * sd_res

df_res_cc <- data.frame(
  obs      = seq_along(res_vec),
  residual = res_vec,
  status   = ifelse(res_vec > ucl_res | res_vec < lcl_res, "Di Luar Batas", "Dalam Batas")
)

ggplot(df_res_cc, aes(x = obs, y = residual)) +
  geom_hline(yintercept = ucl_res, linetype = "dashed", color = "red",   linewidth = 0.7) +
  geom_hline(yintercept = cl_res,  linetype = "solid",  color = "green4", linewidth = 0.7) +
  geom_hline(yintercept = lcl_res, linetype = "dashed", color = "red",   linewidth = 0.7) +
  geom_line(color = "steelblue", linewidth = 0.6) +
  geom_point(aes(color = status), size = 2) +
  scale_color_manual(
    name   = "Status",
    values = c("Dalam Batas" = "steelblue", "Di Luar Batas" = "red")
  ) +
  annotate("text", x = max(df_res_cc$obs), y = ucl_res, label = paste0("UCL = ", round(ucl_res, 1)),
           hjust = 1.05, vjust = -0.4, color = "#990000", size = 3.2) +
  annotate("text", x = max(df_res_cc$obs), y = cl_res,  label = paste0("CL = ",  round(cl_res,  1)),
           hjust = 1.05, vjust = -0.4, color = "#005A00", size = 3.2) +
  annotate("text", x = max(df_res_cc$obs), y = lcl_res, label = paste0("LCL = ", round(lcl_res, 1)),
           hjust = 1.05, vjust =  1.4, color = "#990000", size = 3.2) +
  labs(
    title    = "Control Chart Residual ARIMA — Individual (I-Chart)",
    subtitle = "Garis merah putus-putus = UCL/LCL (±2σ)  |  Garis hijau = center line",
    x        = "Observasi ke-",
    y        = "Nilai Residual",
    caption  = "Titik merah = out-of-control"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title      = element_text(face = "bold", size = 13),
    plot.subtitle   = element_text(color = "gray40", size = 10),
    legend.position = "bottom"
  )

# Peta kendali historis dan prediksi
fc_mean <- as.numeric(fc_terbaik$mean)
fc_lo95 <- as.numeric(fc_terbaik$lower[, 2])
fc_hi95 <- as.numeric(fc_terbaik$upper[, 2])
fc_lo80 <- as.numeric(fc_terbaik$lower[, 1])
fc_hi80 <- as.numeric(fc_terbaik$upper[, 1])

# Batas kendali memakai gabungan data historis dan nilai prediksi.
semua_nilai <- c(as.numeric(idr), fc_mean)
cl_fc  <- mean(semua_nilai)
sd_fc  <- sd(semua_nilai)
ucl_fc <- cl_fc + 2 * sd_fc
lcl_fc <- cl_fc - 2 * sd_fc

n_hist <- length(as.numeric(idr))
df_hist_cc <- data.frame(
  h      = seq_len(n_hist),
  nilai  = as.numeric(idr),
  tipe   = "Historis",
  status = ifelse(as.numeric(idr) > ucl_fc | as.numeric(idr) < lcl_fc,
                  "Di Luar Batas", "Dalam Batas")
)

df_fc_cc <- data.frame(
  h      = n_hist + seq_along(fc_mean),
  mean   = fc_mean,
  lo95   = fc_lo95,
  hi95   = fc_hi95,
  lo80   = fc_lo80,
  hi80   = fc_hi80,
  tipe   = "Prediksi",
  status = ifelse(fc_mean > ucl_fc | fc_mean < lcl_fc, "Di Luar Batas", "Dalam Batas")
)

ggplot() +
  geom_ribbon(data = df_fc_cc, aes(x = h, ymin = lo95, ymax = hi95, fill = "95%"), alpha = 0.20) +
  geom_ribbon(data = df_fc_cc, aes(x = h, ymin = lo80, ymax = hi80, fill = "80%"), alpha = 0.35) +
  geom_hline(yintercept = ucl_fc, linetype = "dashed", color = "red",    linewidth = 0.7) +
  geom_hline(yintercept = cl_fc,  linetype = "solid",  color = "green4", linewidth = 0.7) +
  geom_hline(yintercept = lcl_fc, linetype = "dashed", color = "red",    linewidth = 0.7) +
  geom_vline(xintercept = n_hist + 0.5, linetype = "dotted", color = "gray50", linewidth = 0.6) +
  geom_line(data = df_hist_cc, aes(x = h, y = nilai), color = "#185FA5", linewidth = 0.7) +
  geom_point(data = df_hist_cc, aes(x = h, y = nilai, color = status), size = 1.8) +
  geom_line(data = df_fc_cc, aes(x = h, y = mean), color = "#D85A30", linewidth = 0.9, linetype = "dashed") +
  geom_point(data = df_fc_cc, aes(x = h, y = mean, color = status), size = 2.5, shape = 17) +
  annotate("text", x = max(df_fc_cc$h), y = ucl_fc,
           label = paste0("UCL = ", scales::comma(round(ucl_fc))),
           hjust = 1.05, vjust = -0.4, color = "#990000", size = 3.2) +
  annotate("text", x = max(df_fc_cc$h), y = cl_fc,
           label = paste0("CL = ",  scales::comma(round(cl_fc))),
           hjust = 1.05, vjust = -0.4, color = "#005A00", size = 3.2) +
  annotate("text", x = max(df_fc_cc$h), y = lcl_fc,
           label = paste0("LCL = ", scales::comma(round(lcl_fc))),
           hjust = 1.05, vjust =  1.4, color = "#990000", size = 3.2) +
  annotate("text", x = n_hist + 0.5, y = ucl_fc,
           label = "← Historis | Prediksi →",
           vjust = -0.5, color = "gray40", size = 3.0) +
  scale_color_manual(
    name   = "Status",
    values = c("Dalam Batas" = "steelblue", "Di Luar Batas" = "red")
  ) +
  scale_fill_manual(
    name   = "Interval prediksi",
    values = c("80%" = "#378ADD", "95%" = "#B5D4F4")
  ) +
  scale_y_continuous(labels = scales::label_comma()) +
  labs(
    title    = "Control Chart Nilai Tukar IDR/USD — Historis & Prediksi",
    subtitle = "Batas kendali ±2σ dihitung dari gabungan data historis & prediksi  |  ▲ = titik prediksi  |  ● = data historis",
    x        = "Observasi ke-",
    y        = "Nilai IDR per USD",
    caption  = paste("Sumber: data idr-usd.xlsx | Model:", model_label, "| Titik merah = out-of-control")
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title      = element_text(face = "bold", size = 13),
    plot.subtitle   = element_text(color = "gray40", size = 10),
    plot.caption    = element_text(color = "gray35", size = 8),
    legend.position = "bottom"
  )

# Grafik nilai tukar aktual dan prediksi
df_aktual <- data.frame(
  waktu = as.numeric(time(idr)),
  nilai = as.numeric(idr),
  tipe  = "Aktual"
)

df_fc <- data.frame(
  waktu = as.numeric(time(fc_terbaik$mean)),
  mean  = as.numeric(fc_terbaik$mean),
  lo80  = as.numeric(fc_terbaik$lower[, 1]),
  hi80  = as.numeric(fc_terbaik$upper[, 1]),
  lo95  = as.numeric(fc_terbaik$lower[, 2]),
  hi95  = as.numeric(fc_terbaik$upper[, 2])
)

ggplot() +
  geom_ribbon(data = df_fc, aes(x = waktu, ymin = lo95, ymax = hi95, fill = "95%"), alpha = 0.25) +
  geom_ribbon(data = df_fc, aes(x = waktu, ymin = lo80, ymax = hi80, fill = "80%"), alpha = 0.40) +
  geom_line(data = df_aktual, aes(x = waktu, y = nilai, color = "Aktual"), linewidth = 0.8) +
  geom_line(data = df_fc, aes(x = waktu, y = mean, color = "Forecast"), linewidth = 0.9, linetype = "dashed") +
  geom_point(data = df_fc, aes(x = waktu, y = mean, color = "Forecast"), size = 1.8) +
  geom_vline(xintercept = max(df_aktual$waktu), linetype = "dotted", color = "gray50", linewidth = 0.5) +
  scale_color_manual(name = NULL, values = c("Aktual" = "#185FA5", "Forecast" = "#D85A30")) +
  scale_fill_manual(name = "Interval prediksi", values = c("80%" = "#378ADD", "95%" = "#B5D4F4")) +
  scale_x_continuous(
    breaks = seq(floor(min(df_aktual$waktu)), ceiling(max(df_fc$waktu)), by = 1),
    labels = function(x) as.integer(x)
  ) +
  scale_y_continuous(labels = scales::label_comma()) +
  labs(
    title    = paste("Prediksi nilai tukar IDR/USD dengan", model_label),
    subtitle = "Garis putus-putus = nilai prediksi  |  Pita = interval prediksi 80% dan 95%",
    x        = "Tahun",
    y        = "Nilai IDR per USD",
    caption  = "Sumber: data idr-usd.xlsx"
  ) +
  guides(
    color = guide_legend(order = 1, override.aes = list(linewidth = 1.2)),
    fill  = guide_legend(order = 2)
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(face = "bold", size = 13),
    plot.subtitle    = element_text(color = "gray40", size = 10, margin = margin(b = 8)),
    plot.caption     = element_text(color = "gray35", size = 8),
    legend.position  = "bottom",
    legend.key.width = unit(1.5, "cm"),
    axis.text.x      = element_text(angle = 45, hjust = 1),
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = "gray92")
  )

print(df_fc)
print(df_res_cc$residual)
mean(df_res_cc$residual) - 2*sd(df_res_cc$residual) 
