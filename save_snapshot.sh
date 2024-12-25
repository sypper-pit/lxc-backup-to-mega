#!/bin/bash

set -e  # Прекращает выполнение скрипта при любой ошибке

# Получаем текущую директорию, где находится скрипт
export_path="$(pwd)"

# Запрос имени контейнера
read -p "Enter container name: " container_name

# Получение списка снапшотов
echo "Available snapshots for container $container_name:"
lxc info $container_name | sed -n '/Snapshots:/,/^$/p' | tail -n +2

# Запрос имени снапшота
read -p "Enter snapshot name to save: " snapshot_name

# Формирование уникального имени файла для сохранения
filename="${container_name}_${snapshot_name}_$(date +"%Y%m%d_%H%M%S")_$(lxc version | awk '/Server version:/ {print $3}')_$(hostname -I | awk '{print $1}' | tr '.' '-')"
unique_alias="temp_export_$(date +%s)"

# Сохранение снапшота как временного образа
echo "Creating temporary image..."
lxc publish $container_name/$snapshot_name --alias $unique_alias

# Экспорт образа в текущую директорию
echo "Exporting image..."
lxc image export $unique_alias "$export_path/${filename}.tar.gz"

# Проверка, создался ли файл
if [ -f "$export_path/${filename}.tar.gz" ]; then
    echo "Snapshot exported to: $export_path/${filename}.tar.gz"
else
    echo "Error: Failed to create export file."
fi

# Удаление временного образа
echo "Cleaning up..."
lxc image delete $unique_alias

echo "Operation completed."
