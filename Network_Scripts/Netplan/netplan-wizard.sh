#!/bin/bash

# Este script es un asistente para la configuración de Netplan en sistemas Linux.
# Su propósito es facilitar la creación de un archivo de configuración Netplan válido,
# que especifique la configuración de red para una o varias interfaces de red.

# Se asume que el usuario tiene los permisos adecuados para realizar cambios de configuración
# de red en el sistema y que está familiarizado con los conceptos básicos de redes y direcciones IP.

# Crea el archivo de configuración de Netplan
netplan_config_file="netplan-config.yaml"

# Función para imprimir un mensaje de bienvenida
print_welcome() {
  echo "============================================="
  echo "Asistente de configuración de Netplan en Bash"
  echo "============================================="
  echo ""
}

# Función para imprimir una lista de interfaces de red disponibles
print_interfaces() {
  echo "Interfaces de red disponibles:"
  for i in "${!network_interfaces[@]}"; do
    echo "$((i+1)). ${network_interfaces[i]}"
  done
  echo ""
}

# Función para validar una dirección IP
is_valid_ip_address() {
  local ip=$1

  if [[ -z $ip ]]; then
    return 0
  fi

  if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
    IFS='.' read -ra IP <<< "$ip"
    if [ ${IP[0]} -le 255 ] && [ ${IP[1]} -le 255 ] && [ ${IP[2]} -le 255 ] && [ ${IP[3]%%/*} -le 255 ]; then
      local mask=$(echo "$ip" | awk -F '/' '{print $2}')
      if (( $mask >= 0 && $mask <= 32 )); then
        return 0
      fi
    fi
  fi

  return 1
}

function is_valid_option() {
  [[ "$1" =~ ^(s|S|n|N)$ ]]
}

# Lista las interfaces de red disponibles, excluyendo las inalámbricas
network_interfaces=($(ls /sys/class/net | grep -v '^wl'))

# Llama a las funciones para imprimir el mensaje de bienvenida e interfaces
print_welcome
print_interfaces

# Solicita al usuario seleccionar las interfaces a configurar
read -e -p "Ingrese los números de las interfaces de red que desea configurar (separados por espacio): " -a selected_interfaces

declare -a interface_configs

for index in "${selected_interfaces[@]}"; do
  interface="${network_interfaces[$((index-1))]}"
  echo "Configuración de la interfaz $interface:"

  # Preguntar al usuario si desea continuar
  while ! is_valid_option "$static_ip_enabled"; do
    read -e -p "¿Desea configurar una dirección IP estática? [s/n]: " static_ip_enabled
  done
  
  if [[ "$static_ip_enabled" =~ ^(s|S)$ ]]; then
    dhcp4_enabled="no"
    
    # Validación de dirección IP estática
    valid_ip_address=false
    until $valid_ip_address; do
      read -e -p "Ingrese la dirección IP estática (p. ej., 192.168.1.2/24): " static_ip_address
      if ! is_valid_ip_address "$static_ip_address"; then
        echo "La dirección IP ingresada no es válida. Por favor, inténtalo de nuevo."
      else
        valid_ip_address=true
      fi
    done
    
    read -e -p "Ingrese la puerta de enlace predeterminada (p. ej., 192.168.1.1): " gateway_address
  else
    dhcp4_enabled="yes"
  fi

  interface_config="    $interface:\n      dhcp4: $dhcp4_enabled"

  if [[ "$static_ip_enabled" =~ ^(s|S)$ ]]; then
    interface_config+="\n      addresses:\n        - $static_ip_address"
    if ! [ -z $gateway_address ]; then
      interface_config+="\n      routes:\n        - to: default\n          via: $gateway_address"
    fi
  fi

  if [[ "$static_ip_enabled" =~ ^(s|S)$ ]]; then
    # Pregunta si se deben configurar rutas estáticas
    while ! is_valid_option "$static_routes_enabled"; do
      read -e -p "¿Desea configurar rutas estáticas adicionales? (s/n): " static_routes_enabled
    done
    
    if [[ "$static_routes_enabled" =~ ^(s|S)$ ]]; then
      if [ -z $gateway_address ];then interface_config+="\n      routes:"; fi
      read -e -p "Ingrese el número de rutas estáticas a configurar: " num_static_routes
      for j in $(seq 1 $num_static_routes); do
        read -e -p "Ingrese la ruta $j (p. ej., 10.0.0.0/24 via 192.168.1.1): " static_route
        interface_config+="\n        - to: ${static_route% via *}\n          via: ${static_route#* via }"
      done
    fi
  fi

  if [[ "$static_ip_enabled" =~ ^(s|S)$ ]]; then
  # Pregunta si se deben configurar nameservers
    while ! is_valid_option "$nameservers_enabled"; do
      read -e -p "¿Desea configurar nameservers? (s/n): " nameservers_enabled
    done
    
    if [[ "$nameservers_enabled" =~ ^(s|S)$ ]]; then
      read -e -p "Ingrese el número de nameservers a configurar: " num_nameservers
      interface_config+="\n      nameservers:\n        addresses: ["
      for k in $(seq 1 $num_nameservers); do
        read -e -p "Ingrese el nameserver $k (p. ej., 8.8.8.8): " nameserver_address
        if [ $k -eq $num_nameservers ]; then
          interface_config+="$nameserver_address"
        else
          interface_config+="$nameserver_address, "
        fi
      done
      interface_config+="]"
    fi
  fi

  interface_configs+=("$interface_config")
  echo ""
  static_ip_enabled=
  static_routes_enabled=
  nameservers_enabled=
done

cat > "$netplan_config_file" << EOL
network:
  version: 2
  renderer: networkd
  ethernets:
EOL

for interface_config in "${interface_configs[@]}"
  do
    printf "%b\n" "$interface_config" >> "$netplan_config_file"
  done

echo "Archivo de configuración de Netplan generado: ${netplan_config_file}"

while ! is_valid_option "$hostname_change_enabled"; do
  read -e -p "¿Deseas cambiar el hostname de este equipo? (s/n): " hostname_change_enabled
done

if [[ "$hostname_change_enabled" =~ ^(s|S)$ ]]; then
  echo 
  read -e -p "Por favor ingresa el nuevo hostname: " new_hostname

  echo "Configurando nuevo hostname..."
  echo "$new_hostname" > /etc/hostname
  sed -i "s/127.0.1.1.*/127.0.1.1\t$new_hostname/g" /etc/hosts
  hostname "$new_hostname"
  echo "El hostname ha sido cambiado exitosamente a '$new_hostname'."
fi
hostname_change_enabled=


mv netplan-config.yaml /etc/netplan/00-installer-config.yaml
netplan apply

if ! [[ $(grep root /etc/passwd | cut -d: -f7 | head -n 1) == "/bin/bash" ]]; then 
  usermod --shell /bin/bash root
  bash
fi
