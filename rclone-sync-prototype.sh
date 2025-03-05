#!/bin/bash

# Функція для очікування без зайвих сповіщень
countdown() {
    sleep "$1"
}

# Функція для відправлення сповіщень (опціонально)
send_notification() {
    local summary="$1"
    local body="$2"
    local icon="$3"
    notify-send "$summary" "$body" --icon="$icon"
}

# Очікування 60 секунд перед початком
send_notification "rclone очікування монтування " "Очікування 60 секунд перед початком..." "dialog-information"
sleep 60

# Монтування Google Drive, якщо не змонтовано
if ! mountpoint -q "/perenis/Google Drive/"; then
    send_notification "Монтування Google Drive" "Розпочато монтування..." "drive-upload"
    if ! rclone mount "Google Drive:" "/perenis/Google Drive/" --daemon; then
        send_notification "Помилка монтування" "Не вдалося змонтувати Google Drive." "dialog-error"
        exit 1
    fi
    sleep 10
fi

# Масив директорій для синхронізації
SRC_DIRS=(
    "/home/victor/Garrys_mod_projects/"
    "/home/victor/.local/share/Steam/steamapps/common/GarrysMod/garrysmod/materials/"
    "/home/victor/.local/share/Steam/steamapps/common/GarrysMod/garrysmod/models/"
    "/home/victor/.local/share/Steam/steamapps/common/GarrysMod/garrysmod/maps/"
    "/home/victor/Документи/"
    "/home/victor/Музика/"
    "/home/victor/Картинки/"
    "/home/victor/blender/"
    "/home/victor/drive/"
)

DEST_DIR="/perenis/sync"
REMOTE_DEST="Google Drive:"  # Налаштуйте за потреби

while true; do
    send_notification "Синхронізація файлів" "Не вимикайте комп'ютер під час процесу." "sync"

    total_files=$(find "${SRC_DIRS[@]}" -type f 2>/dev/null | wc -l)
    if [ "$total_files" -eq 0 ]; then
        send_notification "Помилка" "Не знайдено файлів для синхронізації." "dialog-error"
        exit 1
    fi

    processed_files=0
    transferred_bytes=0
    start_time=$(date +%s)

    {
        # Обходимо по кожній директорії зі списку
        for SRC in "${SRC_DIRS[@]}"; do
            # Видаляємо кінцевий слеш та отримуємо ім'я папки
            BASENAME=$(basename "${SRC%/}")
            LOCAL_DEST="${DEST_DIR}/${BASENAME}/"
            REMOTE_DEST_PATH="${REMOTE_DEST}/${BASENAME}/"

            mkdir -p "$LOCAL_DEST"

            # Копіюємо файли з поточної директорії на віддалений диск
            if ! rclone copy "$SRC" "$REMOTE_DEST_PATH" --progress --create-empty-src-dirs; then
                send_notification "Помилка при синхронізації" "Не вдалося синхронізувати $SRC" "dialog-error"
                continue
            fi

            # Локальна синхронізація через rsync
            if ! rsync -av "$SRC" "$LOCAL_DEST"; then
                send_notification "Помилка при локальній синхронізації" "Не вдалося синхронізувати $SRC локально" "dialog-error"
                continue
            fi

            # Підраховуємо кількість файлів і сумарний розмір у поточній директорії
            count=$(find "$SRC" -type f 2>/dev/null | wc -l)
            dir_size=$(find "$SRC" -type f -printf "%s\n" 2>/dev/null | awk '{sum+=$1} END {print sum}')
            processed_files=$(( processed_files + count ))
            transferred_bytes=$(( transferred_bytes + dir_size ))

            # Обчислення відсотку завершення
            progress=$(( processed_files * 100 / total_files ))

            # Обчислення швидкості (файлів за секунду)
            current_time=$(date +%s)
            elapsed=$(( current_time - start_time ))
            if [ "$elapsed" -gt 0 ]; then
                speed=$(( processed_files / elapsed ))
            else
                speed=0
            fi

            # Обчислення обсягу перенесених даних у ГБ (з точністю до 2 знаків)
            gb_transferred=$(echo "scale=2; $transferred_bytes/(1024*1024*1024)" | bc)

            # Оновлення повідомлення для Zenity. Рядок, що починається з '#' оновлює текст.
            echo "# Синхронізовано: $processed_files з $total_files файлів, Швидкість: ${speed} ф/с, Перенесено: ${gb_transferred} ГБ"
            echo "$progress"
        done
    } | zenity --progress \
               --title="Синхронізація файлів" \
               --text="Синхронізація в процесі... Не вимикайте комп'ютер." \
               --percentage=0 \
               --auto-close \
                --no-cancel \
                --no-display

    if [ $? -eq 0 ]; then
        send_notification "Синхронізація завершена" "Всі файли успішно синхронізовані. Повторення через 30 хвилин." "dialog-information"
    else
        send_notification "Синхронізація перервана" "Виникла помилка під час синхронізації." "dialog-error"
    fi

    countdown 1800  # Чекаємо 30 хвилин перед наступною синхронізацією
done
