import Darwin
import Foundation

/// The memory of this process as the system charges it (C-SCALE-02).
public enum ProcessMemory {
    /// `phys_footprint` of `task_info(TASK_VM_INFO)`, in bytes: what Activity Monitor shows
    /// as the process's memory. Nil when the system does not answer.
    public static var footprint: UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }

    /// A number of bytes in mebibytes with one decimal, for reports.
    public static func megabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f MiB", Double(bytes) / 1_048_576)
    }
}

/// The files this process has open, by path (C-SCALE-02): a test can see where a file it
/// does not name is being written, and that it was closed.
public enum OpenFiles {
    /// The paths of the vnodes this process has open: files and folders, not sockets or
    /// pipes. Empty when the system does not answer.
    public static func paths() -> [String] {
        let pid = getpid()
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride + 16)
        let filled = descriptors.withUnsafeMutableBytes {
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
        }
        guard filled > 0 else { return [] }
        var paths: [String] = []
        for descriptor in descriptors.prefix(Int(filled) / stride)
            where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE)
        {
            var info = vnode_fdinfowithpath()
            let read = proc_pidfdinfo(
                pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info,
                Int32(MemoryLayout<vnode_fdinfowithpath>.size))
            guard read == Int32(MemoryLayout<vnode_fdinfowithpath>.size) else { continue }
            let path = withUnsafeBytes(of: info.pvip.vip_path) { raw in
                String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? ""
            }
            paths.append(path)
        }
        return paths
    }
}
