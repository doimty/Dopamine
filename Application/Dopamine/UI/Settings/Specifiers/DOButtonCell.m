//
//  DOButtonCell.m
//  Dopamine
//
//  Created by tomt000 on 26/01/2024.
//

#import "DOButtonCell.h"
#import "DOActionMenuButton.h"
#import "DOGlobalAppearance.h"
#import "DOUIManager.h"

@implementation DOButtonCell

- (id)initWithStyle:(long long)arg1 reuseIdentifier:(id)arg2 specifier:(PSSpecifier *)specifier
{
    self = [super init];
    if (self)
    {
        UIAction *action = [UIAction actionWithTitle:DOLocalizedString([specifier propertyForKey:@"title"]) image:[UIImage systemImageNamed:[specifier propertyForKey:@"image"] withConfiguration:[DOGlobalAppearance smallIconImageConfiguration]] identifier:[specifier propertyForKey:@"key"] handler:^(__kindof UIAction * _Nonnull action) {
            SEL selector = NSSelectorFromString([specifier propertyForKey:@"action"]);
            if ([[specifier target] respondsToSelector:selector]) {
                [[specifier target] performSelector:selector withObject:specifier];
            }
        }];

        DOActionMenuButton *button = [DOActionMenuButton buttonWithAction:action chevron:NO];

        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.tintColor = [UIColor systemBlueColor];
        [button setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];
        UIButtonConfiguration *configuration = button.configuration;
        configuration.baseForegroundColor = [UIColor systemBlueColor];
        button.configuration = configuration;

        [self.contentView addSubview:button];

        [NSLayoutConstraint activateConstraints:@[
            [button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [button.topAnchor constraintEqualToAnchor:self.topAnchor],
            [button.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        ]];
    }
    return self;
}

@end
