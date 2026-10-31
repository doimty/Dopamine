//
//  DOHeaderCell.m
//  Dopamine
//
//  Created by tomt000 on 26/01/2024.
//

#import "DOHeaderCell.h"

@implementation DOHeaderCell

- (id)initWithSpecifier:(PSSpecifier*)specifier
{
    if (self = [super init])
    {
        UILabel *titleLabel = [[UILabel alloc] init];
        [titleLabel setText:[specifier propertyForKey:@"title"]];
        [titleLabel setFont:[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]];
        [titleLabel setTextColor:[UIColor secondaryLabelColor]];
        titleLabel.textAlignment = NSTextAlignmentLeft;
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        
        [self.contentView addSubview:titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20],
            [titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20],
            [titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor constant:-2]
        ]];

        UIView *border = [[UIView alloc] init];
        border.translatesAutoresizingMaskIntoConstraints = NO;
        border.backgroundColor = [UIColor separatorColor];
        [self.contentView addSubview:border];

        [NSLayoutConstraint activateConstraints:@[
            [border.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
            [border.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20],
            [border.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2],
            [border.heightAnchor constraintEqualToConstant:1]
        ]];
    }
    return self;
}

- (CGFloat)preferredHeightForWidth:(CGFloat)width
{
	return 36;
}

@end
