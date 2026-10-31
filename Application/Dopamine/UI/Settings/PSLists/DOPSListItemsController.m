//
//  DOPSListItemsController.m
//  Dopamine
//
//  Created by tomt000 on 26/01/2024.
//

#import "DOPSListItemsController.h"
#import "DOPSListController.h"

@interface DOPSListItemsController ()

@end

@implementation DOPSListItemsController

- (void)viewDidLoad {
    [super viewDidLoad];

    [_table setSeparatorColor:[UIColor separatorColor]];
    [_table setBackgroundColor:[UIColor clearColor]];
    [DOPSListController setupViewControllerStyle:self];

    _table.tableHeaderView = [DOPSListItemsController makeHeader:((PSSpecifier*)self.specifier).name withTarget:self];
}

+ (UIView *)makeHeader:(NSString *)title withTarget:(id)target
{
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 58)];

    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    label.textColor = [UIColor labelColor];
    label.textAlignment = NSTextAlignmentLeft;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:label];

    UIView *border = [[UIView alloc] init];
    border.translatesAutoresizingMaskIntoConstraints = NO;
    border.backgroundColor = [UIColor separatorColor];
    [header addSubview:border];

    UIImage *backImage = [UIImage systemImageNamed:@"chevron.left" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightMedium]];
    backImage = [backImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [backButton setImage:backImage forState:UIControlStateNormal];
    [backButton setTintColor:[UIColor systemBlueColor]];
    [backButton addTarget:target action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    backButton.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:backButton];

    [NSLayoutConstraint activateConstraints:@[
        [backButton.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:12],
        [backButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [backButton.widthAnchor constraintEqualToConstant:32],
        [backButton.heightAnchor constraintEqualToConstant:32],
        [label.leadingAnchor constraintEqualToAnchor:backButton.trailingAnchor constant:8],
        [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [label.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [border.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [border.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [border.bottomAnchor constraintEqualToAnchor:header.bottomAnchor],
        [border.heightAnchor constraintEqualToConstant:1],
    ]];

    return header;
}

- (void)dismiss {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    _table.frame = CGRectMake(12, 5, self.view.bounds.size.width - 24, self.view.bounds.size.height - 10);
}

#pragma mark - Status Bar

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleDefault;
}


@end
