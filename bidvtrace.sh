#!/bin/bash

cmd=$(basename "$0")
baseDir="/var/logs/bidvomni"

# --- Lấy danh sách hệ thống ---
get_systems_list() {
    for d in "$baseDir"/*/; do
        name="${d%/}"
        name="${name##*/}"
        [[ "$name" == *[![:space:]]* && "$name" == *srv* ]] && echo "$name"
    done | sort
}

# --- Hiển thị hướng dẫn ---
show_help() {
    systems_list=$(get_systems_list | tr '\n' ' ')
    echo "Usage: $cmd [OPTIONS] <search_value> [system_name...]"
    echo
    echo "Options:"
    echo "  -z            Tìm trong file .gz"
    echo "  -t            Tối ưu tìm kiếm requestId (ví dụ: [10230123]). Dừng lại không tìm ở module khác nếu tìm thấy log"
    echo "  -m <MM>       Chỉ định tháng (01–12), mặc định ko truyền lấy tháng hiện tại"
    echo "  -h            Hiển thị hướng dẫn"
    echo
    echo "Available Systems: $systems_list"
    exit 0
}

# --- Tìm log ---

search_in_gz_file() {
    local gz_file="$1"
    # Tìm nhanh bằng zgrep -q
    if zgrep -q -- "$search_value" "$gz_file"; then
        # Dùng zcat + awk để hiển thị chi tiết
        zcat "$gz_file" 2>/dev/null | awk -v value="$search_pattern" '
            BEGIN { found=0; printed=0 }
            {
                if (gsub(value, "\033[31m&\033[0m")) {
                    found=1
                    printed=1
                    print
                    next
                }
                if (found == 1 && !/\[mid/ && !/^$/) {
                    print
                    next
                }
                if ((found == 1 && (/\[mid/ || /^$/)) || found == 0) {
                    found=0
                    next
                }
            }
            END { exit (printed == 0) }
        '
        return $?
    fi
    return 1
}

            # Cleanup function to kill background processes
cleanup() {
    echo -e "\n  Đang dọn dẹp tiến trình nền..."
    pkill -P $$ 2>/dev/null
    [ -f "$result_file" ] && rm -f "$result_file"
    exit 130  # 130 = Ctrl+C
}

# Bắt tín hiệu Ctrl+C
trap cleanup SIGINT

search_logs() {
    local system="$1"
    local search_pattern="$2"
    local use_gz="$3"
    local target_month="$4"

    local sysDir="$baseDir/$system"

    if [ "$use_gz" -eq 1 ]; then
      local month_dir="${sysDir}/${system}-$(date +%Y)-${month}"
        if [ ! -d "$month_dir" ]; then
            echo "❌ Không tìm thấy thư mục tháng $(date +%Y)-$month cho hệ thống $system"
            return 1
        fi

        # Lấy danh sách file .log.gz mới nhất trước
        local gz_files=()
        while IFS= read -r -d '' file; do
            gz_files+=("$file")
        done < <(find "$month_dir" -maxdepth 1 -type f -name '*.log*' -print0 | sort -V -z -r)

        if [ ${#gz_files[@]} -eq 0 ]; then
            echo "❌ Không có file .log.gz trong $month_dir"
            return 1
        fi

        echo -e "\n--- $system :: $month_dir ---"

        # Tìm song song tối đa 4 tiến trình
        local pids=()
        #local temp_dir=$(mktemp -d)
        local idx=0
	found_flag="/tmp/found.flag"
        rm -f "$found_flag"

        for gz_file in "${gz_files[@]}"; do
		idx=$((idx + 1))           # cập nhật ngay ở đây
    		this_idx=$idx              # giữ giá trị cố định cho mỗi tiến trình
        {
	    # Nếu đã có file cờ, dừng ngay
            [[ -f "$found_flag" ]] && exit 0
            local start_time=$(date +%s%3N)
            local temp_file="$temp_dir/result_$idx.txt"
 
	    local this_file="$gz_file"
	    local pattern="$search_pattern"
	    # echo "🔍 Searching in $this_file with id: $idx and pattern: $pattern"
        if [[ "$this_file" == *.gz ]]; then
    # Dùng zgrep và zcat cho file .gz
    if zgrep -q -- "$pattern" "$this_file"; then
        zcat "$this_file" 2>/dev/null | awk -v value="$pattern" '
            BEGIN { found=0; printed=0 }
            {
                if (gsub(value, "\033[31m&\033[0m")) {
                    found=1
                    printed=1
                    print
                    next
                }
                if (found == 1 && !/\[mid/ && !/^$/) {
                    print
                    next
                }
                if ((found == 1 && (/\[mid/ || /^$/)) || found == 0) {
                    found=0
                    next
                }
            }
            END { exit (printed == 0) }
        '
        touch "$found_flag"
        echo "🎯 Found in $(basename "$gz_file")"	
    fi
elif [[ "$this_file" == *.log ]]; then
    # Dùng grep và cat cho file .log
    if grep -q -- "$pattern" "$this_file"; then
        cat "$this_file" | awk -v value="$pattern" '
            BEGIN { found=0; printed=0 }
            {
                if (gsub(value, "\033[31m&\033[0m")) {
                    found=1
                    printed=1
                    print
                    next
                }
                if (found == 1 && !/\[mid/ && !/^$/) {
                    print
                    next
                }
                if ((found == 1 && (/\[mid/ || /^$/)) || found == 0) {
                    found=0
                    next
                }
            }
            END { exit (printed == 0) }
        '
        touch "$found_flag"
        echo "🎯 Found in $(basename "$gz_file")"	
    fi
fi
	  [[ -f "$found_flag" ]] && exit 0
            local end_time=$(date +%s%3N)
            local duration=$((end_time - start_time))
            # echo "⏱ Find in $(basename "$gz_file") spent $duration ms"
        } &

        pids+=($!)

        # Giới hạn 16 tiến trình chạy song song
        while [ "${#pids[@]}" -ge 32 ]; do
            # Nếu đã tìm thấy => thoát sớm không chờ thêm
    		if [ -f "$found_flag" ]; then
        	break
    		fi
		
		wait -n
            # Cập nhật lại danh sách tiến trình còn chạy
            temp_pids=()
            for pid in "${pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    temp_pids+=("$pid")
                fi
            done
            pids=("${temp_pids[@]}")
        done

        done

        wait

        # Tổng hợp kết quả
        #if compgen -G "$temp_dir/result_*.txt" > /dev/null; then
        #    cat "$temp_dir"/result_*.txt
        #    rm -rf "$temp_dir"
        #    return 0
        #else
        #    rm -rf "$temp_dir"
        #    echo "❌ Không tìm thấy log khớp"
        #    return 1
        #fi
    else
        if ! compgen -G "$sysDir/*.log" > /dev/null; then
            echo "❌ Không có file .log trong $sysDir"
            return 1
        fi

        echo -e "\n--- $system :: *.log ---"
        awk -v value="$search_pattern" '
            BEGIN { printed=0 }
            gsub(value, "\033[31m&\033[0m") { found = 1; print; printed = 1; next }
            found == 1 && !/\[mid/ && !/^$/ { print; next }
            found == 1 && (/\[mid/ || /^$/) || found == 0 { found = 0; next }
            END {
                exit (printed == 0)
            }
        ' "$sysDir"/*.log
        return $?
    fi
}

# --- Xử lý tham số ---
search_value=""
search_gz=0
optimize_requestid=0
month=""
systems=()

while getopts ":ztm:h" opt; do
    case $opt in
        z) search_gz=1 ;;
        t) optimize_requestid=1 ;;
        m)
            if [[ "$OPTARG" =~ ^[0-9]{1,2}$ ]]; then
                                # Nếu chỉ 1 ký tự thì thêm 0 đằng trước
                                if [[ ${#OPTARG} -eq 1 ]]; then
                                        month="0$OPTARG"
                                else
                                        month="$OPTARG"
                                fi
                                # Kiểm tra tháng có hợp lệ từ 01 đến 12 không
                                if ! [[ "$month" =~ ^(0[1-9]|1[0-2])$ ]]; then
                                        echo "❌ Tháng không hợp lệ: $month (chỉ chấp nhận 01-12)"
                                        exit 1
                                fi
                        else
                                echo "❌ Tháng không hợp lệ: $OPTARG (phải là số từ 1 đến 12)"
                                exit 1
                        fi
                        ;;
        h) show_help ;;
        \?) echo "❌ Tùy chọn không hợp lệ: -$OPTARG" >&2; show_help ;;
    esac
done
shift $((OPTIND -1))

# --- Kiểm tra search_value ---
if [ $# -lt 1 ]; then
    echo "❌ Thiếu tham số bắt buộc <search_value>"
    show_help
fi
search_value="$1"
shift

# --- Nếu dùng -z mà không truyền tháng, thì lấy tháng hiện tại ---
if [ "$search_gz" -eq 1 ] && [ -z "$month" ]; then
    month=$(date +%m)
fi

# --- Danh sách hệ thống cần tìm ---
if [ $# -gt 0 ]; then
    mapfile -t systems < <(get_systems_list | grep -wFf <(printf "%s\n" "$@"))
else
    mapfile -t systems < <(get_systems_list)
fi

if [ ${#systems[@]} -eq 0 ]; then
    echo "❌ Không tìm thấy hệ thống phù hợp"
    exit 1
fi

# --- Tạo pattern tìm kiếm ---
if [ $optimize_requestid -eq 1 ]; then
    search_pattern="\\\\[${search_value}\\\\]"
else
    search_pattern="${search_value}"
fi

# --- Tìm kiếm ---
found_log=0
start_time=$(date +%s%3N)
for sys in "${systems[@]}"; do
    if search_logs "$sys" "$search_pattern" "$search_gz" "$month"; then
            found_log=1
            if [ "$optimize_requestid" -eq 1 ]; then
                    break
            fi
    fi
done
end_time=$(date +%s%3N)
duration=$((end_time - start_time))
echo "⏱ Xử lý trong ${duration} ms"
if [ "$found_log" -eq 1 ]; then
    echo -e "\n🎉 Đã tìm được log!"
else
    echo -e "\n😢 Không tìm thấy log!"
fi