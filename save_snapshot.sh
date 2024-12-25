#!/bin/bash

# Получаем текущую директорию, где находится скрипт
export_path="$(pwd)"

# Запрос имени контейнера
read -p "Enter container name: " container_name

# Получение списка снапшотов
echo "Available snapshots for container $container_name:"
lxc info $container_name | sed -n '/Snapshots:/,/^$/p' | tail -n +2

# Запрос имени снапшота
read -p "Enter snapshot name to save: " snapshot_name

# Формирование имени файла для сохранения
filename="${container_name}_${snapshot_name}_$(date +"%Y%m%d_%H%M%S")_$(lxc version | awk '/Server version:/ {print $3}')_$(hostname -I | awk '{print $1}')"

# Сохранение снапшота как образа
lxc publish $container_name/$snapshot_name --alias $filename

# Экспорт образа в текущую директорию
lxc image export $filename $export_path/$filename

echo "Snapshot exported to: $export_path/$filename.tar.gz"
