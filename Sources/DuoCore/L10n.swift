import Foundation

/// Apple .strings property lists; Bundle follows the user's preferred app/system language.
public enum L10n {
    public static func text(_ key: String) -> String {
        Bundle.module.localizedString(forKey:key,value:key,table:nil)
    }
    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format:text(key),locale:Locale.current,arguments:arguments)
    }
    static func strings(for language: String) -> [String:String]? {
        guard let url = Bundle.module.url(forResource:"Localizable",withExtension:"strings",subdirectory:nil,localization:language),
              let data = try? Data(contentsOf:url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from:data,format:nil)) as? [String:String]
    }
}
