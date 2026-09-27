#!/usr/bin/env bash

# Останавливаем выполнение скрипта при возникновении ошибки.
# -e — завершить выполнение при ошибке команды.
# -u — считать обращение к необъявленной переменной ошибкой.
# -x — выводить выполняемые команды в консоль.
# pipefail — считать ошибкой весь pipeline, если ошиблась любая команда.
set -euxo pipefail

# =============================
# Установка необходимых пакетов
# =============================

# Устанавливаем:
# epel-release                 — подключение репозитория EPEL;
# dnf-plugins-core             — дополнительные команды для управления DNF;
# httpd                        — Apache HTTP Server;
# curl                         — утилита для проверки HTTP;
# procps-ng                    — набор системных утилит, включая ps;
# policycoreutils-python-utils — утилиты для управления политиками SELinux.
dnf -y install epel-release dnf-plugins-core httpd curl procps-ng policycoreutils-python-utils

# В CentOS Stream 9 включаем репозиторий CRB. Он может потребоваться для зависимостей некоторых пакетов EPEL.
# Если CRB уже включён или команда завершится ошибкой, установка не прерывается благодаря "|| true".
dnf config-manager --set-enabled crb || true

# Устанавливаем пакет lighttpd-fastcgi.
# В используемой версии CentOS Stream 9 отдельная программа spawn-fcgi не предоставляется этим пакетом, поэтому ниже собираем spawn-fcgi из исходников.
dnf -y install lighttpd-fastcgi

# Устанавливаем инструменты, необходимые для сборки spawn-fcgi из исходников.
# spawn-fcgi является отдельным проектом lighttpd.
dnf -y install git meson gcc make pkgconf-pkg-config

# Переходим во временный каталог для сборки.
cd /tmp

# Удаляем старый исходный каталог, если он остался от предыдущего provisioning.
rm -rf spawn-fcgi

# Proxy для доступа к внешним ресурсам. Используется только при клонировании spawn-fcgi.
GIT_PROXY="http://username:password@proxy.example.com:8080"

# Получаем официальный исходный код spawn-fcgi.
git -c http.proxy="$GIT_PROXY" clone https://git.lighttpd.net/lighttpd/spawn-fcgi.git

# Переходим в каталог исходников.
cd /tmp/spawn-fcgi

# Создаём каталог для сборки.
meson setup build --prefix=/usr/local

# Компилируем spawn-fcgi.
meson compile -C build

# Устанавливаем собранную программу.
meson install -C build

# Показываем версию установленной программы.
/usr/local/bin/spawn-fcgi -v

# =============================
# Задание № 1 — мониторинг лога
# =============================

# Копируем systemd service. Этот service выполняет одну проверку лог-файла.
install -m 0644 /vagrant/files/log-monitor.service /etc/systemd/system/log-monitor.service

# Копируем systemd timer. Timer будет запускать log-monitor.service каждые 30 секунд.
install -m 0644 /vagrant/files/log-monitor.timer /etc/systemd/system/log-monitor.timer

# Копируем скрипт, который непосредственно проверяет наличие ключевого слова в указанном файле лога.
install -m 0755 /vagrant/files/log-monitor.sh /usr/local/bin/log-monitor.sh

# Копируем файл с настройками мониторинга.
# В нём задаются:
# LOG_FILE — какой файл проверять;
# KEYWORD  — какое ключевое слово искать.
install -m 0644 /vagrant/files/log-monitor.sysconfig /etc/sysconfig/log-monitor

# ===========================================
# Задание № 2 — перевод spawn-fcgi на systemd
# ===========================================

# Устанавливаем собственный systemd unit для spawn-fcgi.
# Название service специально оставляем spawn-fcgi.service, как требует задание.
install -m 0644 /vagrant/files/spawn-fcgi.service /etc/systemd/system/spawn-fcgi.service

# Устанавливаем файл конфигурации spawn-fcgi.
# Здесь задаются адрес, порт и запускаемая FastCGI-программа.
install -m 0644 /vagrant/files/spawn-fcgi.sysconfig /etc/sysconfig/spawn-fcgi

# Устанавливаем тестовое FastCGI--приложение.
# Оно используется для проверки работы spawn-fcgi.service.
install -m 0755 /vagrant/files/fcgi-testing /usr/local/bin/fcgi-testing

# ==========================================
# Задание № 3 — несколько экземпляров Apache
# ==========================================

# Устанавливаем template unit Apache.
# Символ "%i" будет заменён systemd на имя экземпляра.
# Например:
# httpd@instance1.service
# httpd@instance2.service
install -m 0644 /vagrant/files/httpd@.service /etc/systemd/system/httpd@.service

# Устанавливаем конфигурацию первого экземпляра Apache.
install -m 0644 /vagrant/files/httpd-instance1.conf /etc/httpd/conf.d/httpd-instance1.conf

# Устанавливаем конфигурацию второго экземпляра Apache.
install -m 0644 /vagrant/files/httpd-instance2.conf /etc/httpd/conf.d/httpd-instance2.conf

# ===========================
# Подготовка каталогов Apache
# ===========================

# Создаём отдельные каталоги документов для двух независимых экземпляров Apache.
mkdir -p /var/www/instance1 /var/www/instance2

# Создаём отдельные каталоги для PID-файлов. Каждый экземпляр Apache должен иметь свой PID-файл.
mkdir -p /var/run/httpd-instance1 /var/run/httpd-instance2

# Устанавливаем тестовую HTML-страницу первого экземпляра.
install -m 0644 /vagrant/files/index1.html /var/www/instance1/index.html

# Устанавливаем тестовую HTML-страницу второго экземпляра.
install -m 0644 /vagrant/files/index2.html /var/www/instance2/index.html

# Удаляем стандартную welcome-конфигурацию Apache, чтобы она не мешала работе наших экземпляров.
rm -f /etc/httpd/conf.d/welcome.conf

# ============================
# Настройка SELinux для Apache
# ============================

# Разрешаем Apache использовать нестандартные TCP-порты 8081 и 8082. Они используются нашими двумя экземплярами Apache.
# Если порт ещё не зарегистрирован в SELinux:
# semanage port -a ...
# Если порт уже существует:
# semanage port -m ...
# Такая конструкция позволяет безопасно повторно запускать provisioning.
semanage port -a -t http_port_t -p tcp 8081 2>/dev/null || semanage port -m -t http_port_t -p tcp 8081
semanage port -a -t http_port_t -p tcp 8082 2>/dev/null || semanage port -m -t http_port_t -p tcp 8082

# =============================
# Остановка стандартного Apache
# =============================

# Отключаем стандартный httpd.service и, если он запущен, останавливаем его.
# Это необходимо, потому что наши экземпляры Apache будут запускаться через:
# httpd@instance1.service
# httpd@instance2.service
# "|| true" не позволяет provisioning завершиться ошибкой, если стандартный сервис ещё не был запущен.
systemctl disable --now httpd.service 2>/dev/null || true

# =================================
# Перечитываем конфигурацию systemd
# =================================

# После добавления новых unit-файлов systemd необходимо перечитать конфигурацию.
systemctl daemon-reload

# ===============
# Запуск сервисов
# ===============

# Включаем timer в автозагрузку и сразу запускаем его.
# Timer будет запускать log-monitor.service каждые 30 секунд.
systemctl enable --now log-monitor.timer

# Включаем spawn-fcgi в автозагрузку и сразу запускаем сервис.
systemctl enable --now spawn-fcgi.service

# Включаем первый экземпляр Apache и запускаем его.
# Его конфигурация:
# /etc/httpd/conf.d/httpd-instance1.conf
# Он слушает порт 8081.
systemctl enable --now httpd@instance1.service

# Включаем второй экземпляр Apache и запускаем его.
# Его конфигурация:
# /etc/httpd/conf.d/httpd-instance2.conf
# Он слушает порт 8082.
systemctl enable --now httpd@instance2.service

# ================================
# Проверка результата provisioning
# ================================

# Показываем состояние timer мониторинга.
# "|| true" используется, чтобы ошибка status не остановила весь provisioning.
systemctl --no-pager --full status log-monitor.timer || true

# Показываем состояние spawn-fcgi.
systemctl --no-pager --full status spawn-fcgi.service || true

# Показываем состояние первого экземпляра Apache.
systemctl --no-pager --full status httpd@instance1.service || true

# Показываем состояние второго экземпляра Apache.
systemctl --no-pager --full status httpd@instance2.service || true

# =======================
# Проверка сетевых портов
# =======================

# Показываем TCP-порты, которые сейчас прослушиваются.
# В результате должны быть видны как минимум:
# 8081 — Apache instance1;
# 8082 — Apache instance2;
# 9000 — spawn-fcgi.
ss -lntp

# ===========
# HTTP-ответы
# ===========

# Проверяем HTTP-ответ первого экземпляра Apache.
curl -f http://127.0.0.1:8081/

# Проверяем HTTP-ответ второго экземпляра Apache.
curl -f http://127.0.0.1:8082/
