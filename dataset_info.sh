#!/bin/sh

ROOT="/home/nzheludkov/phd/ml-critical-path-prediction/dataset/load_prediction"
OUT="$ROOT/metrics_all.csv"

# создать / очистить выходной файл
> "$OUT"

header_written=0

for d in "$ROOT"/*; do
    if [ -d "$d" ]; then
        f="$d/metrics.csv"

        # если файл существует и не пустой
        if [ -s "$f" ]; then

            if [ "$header_written" -eq 0 ]; then
                # записываем header первого найденного файла
                head -n 1 "$f" > "$OUT"
                header_written=1
            fi

            # добавляем данные без header
            tail -n +2 "$f" | sed 's/\r$//' >> "$OUT"
        fi
    fi
done

echo "Created: $OUT"